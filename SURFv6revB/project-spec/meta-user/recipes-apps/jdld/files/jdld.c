/*
 * jdld: P.S. Allison <allison.122@osu.edu> 10/3/24
 *
 * jdld is a simple program to watch for commands to dump data from
 * a reserved memory mailbox. why in god's name would you want this?
 * hey, sometimes you have no other way to transfer data than JTAG!
 *
 * the way this works is that there's a 1M region of RAM which Linux
 * doesn't use that the JTAG debugger can dump data to.
 * that transfer is quickish, almost MB/s! so it's not a bad option.
 *
 * automating this purely through jtag requires the jtag terminal:
 * - jdownload connects to a running xsct/xsdb
 * - it gets xsct's current working directory
 * - it changes xsct's current working directory to its current directory
 * - it spawns a jtag terminal it can connect to, and opens it
 * - it identifies the prompt
 * - it spawns a bridge to jdld by running the jb script
 * X it opens a new file by writing O<filename> in the terminal
 *   if jdld responds with ?, it is currently processing a file,
 *   and jdownload sends 'D0\n' to finish it, and repeats X 
 * Y it chunks off up to 1MB from the target file into a 'chunk' file
 * - it executes dow -data chunk 0x70000000
 * - it writes D<size>\n in the terminal if this is the last chunk
 *   (meaning <size> is less than 1MB)
 *   otherwise it just writes D\n and goes to step Y
 *
 * each command from jdld is responded to with K\n if everything's OK,
 * or ?\n if it has no idea what the eff you're talking about (e.g.
 * O when a file's already open). It also responds with V followed by
 * a version string with a V command.
 *
 * this program is scary scary: you MUST have a reserved section of
 * memory at the jtag_mailbox otherwise you could make things go boom
 */

// include all the damn headers
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <stdio.h>
#include <errno.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <signal.h>
#include <stdint.h>

#define VERSION "1.0"

// this is here to allow you to shutoff the actual mailbox dump
// to test out commandy-stuff on a separate computer
// if you comment this out, it actually opens /dev/null and never
// actually tries to read from it (not that it would matter)
#define ACTUALLY_DO_THE_SCARY_THING

const char *command_fifo = "/tmp/jdld-cmd";
const char *response_fifo = "/tmp/jdld-rsp";
#ifdef ACTUALLY_DO_THE_SCARY_THING
const char *devmem = "/dev/mem";
#else
const char *devmem = "/dev/null";
#endif
const off_t jtag_mailbox = 0x70000000;
const ssize_t jtag_mailbox_size = (1<<20);

int stop_requested = 0;

// signal handler
// we catch 'em all
void sig_handler(int signo)
{
  if (signo == SIGINT ||
      signo == SIGTERM ||
      signo == SIGHUP ||
      signo == SIGQUIT) {
    stop_requested = 1;
  }
}


// jdld obviously needs two fifos, an in and an out
// jdld-cmd and jdld-rsp
int main() {
  uint64_t *mbox_vptr;
  char *lbuf = NULL;
  FILE *cmd = NULL;
  FILE *rsp = NULL;
  int memfd = -1;
  int destfd = -1;
  
  ssize_t nb;
  size_t mx = 80;
  struct sigaction act;
  act.sa_handler = &sig_handler;
  sigfillset(&act.sa_mask);
  // we want EINTR to bork getline
  act.sa_flags = 0;
  sigaction(SIGINT, &act, NULL);
  sigaction(SIGTERM, &act, NULL);
  sigaction(SIGHUP, &act, NULL);
  sigaction(SIGQUIT, &act, NULL);
  
  // screw you process umask
  umask(0000);
  // get the line buffer
  lbuf = (char *) malloc(sizeof(char)*mx);
  if (lbuf == NULL) {
    perror("jdld: error allocating line buffer\n");
    exit(1);
  }
  // get the inouts
  printf("jdld: creating command fifo at %s\n", command_fifo);
  if (mkfifo(command_fifo, 0666) != 0) {
    perror("error creating cmd fifo");
    goto cleanup;
  }
  printf("jdld: opening command fifo at %s\n", command_fifo);
  cmd = fopen(command_fifo, "r+");
  if (cmd == NULL) {
    perror("error opening cmd fifo");
    unlink(command_fifo);
    goto cleanup;
  }
  printf("jdld: creating response fifo at %s\n", response_fifo);
  if (mkfifo(response_fifo, 0666) != 0) {
    perror("error creating rsp fifo");
    goto cleanup;
  }
  printf("jdld: opening response fifo at %s\n", response_fifo);
  rsp = fopen(response_fifo, "r+");
  if (rsp == NULL) {
    perror("error opening rsp fifo");
    unlink(response_fifo);
    goto cleanup;
  }  
  printf("jdld: opening %s\n", devmem);
  memfd = open(devmem, O_RDONLY | O_SYNC);
  if (memfd == -1) {
    perror("error opening devmem");
    goto cleanup;
  }
  
  setlinebuf(rsp);
  setlinebuf(cmd);
  fflush(stdout);
  while (!stop_requested) {
    nb = getline(&lbuf, &mx, cmd);
    if (nb != -1) {
      printf("jdld: received string %s", lbuf);
      printf("jdld: string is %ld bytes\n", nb);
      if (lbuf[0] == 'V') {
	printf("jdld: got version request\n");
	fprintf(rsp, "V %s\n", VERSION);
      }
      else if (lbuf[0] == 'C') {
	const char *fnp = &lbuf[1];
	printf("jdld: got create command\n");
	if (destfd == -1) {
	  // strip the newline, you better not eff this up
	  lbuf[nb - 1] = 0;
	  printf("jdld: creating file %s\n", fnp);
	  destfd = creat(fnp, 0666);
	  printf("jdld: destfd is %d\n", destfd);
	  fprintf(rsp, "K\n");
	} else {
	  printf("jdld: but a file is open??\n");
	  fprintf(rsp, "?\n");
	}
      }
      else if (lbuf[0] == 'D') {
	printf("jdld: got chunk command\n");
	// file needs to be open
	if (destfd == -1) {
	  printf("jdld: but no file is open??\n");
	  fprintf(rsp, "?\n");
	  continue;
	} else if (lbuf[1] != 0x0A && lbuf[1] != 0x20) {
	  const char *unk = &lbuf[1];
	  printf("jdld: incorrect D command, needs 0x0A or space: %s\n", unk);
	  fprintf(rsp, "?\n");
	  continue;
	} else {
	  size_t chunk_size;
	  ssize_t wb = 0;
	  if (lbuf[1] == 0x0A) {
	    chunk_size = jtag_mailbox_size;
	  } else {
	    const char *sizeptr = lbuf + 1;
	    // strip the newline. again, don't eff this up.
	    lbuf[nb - 1] = 0;
	    chunk_size = strtoul(sizeptr, NULL, 0);
	    if (chunk_size > jtag_mailbox_size) {
	      printf("jdld: but size too large: %s\n", sizeptr);
	      fprintf(rsp, "?\n");
	      continue;
	    }
	  }
	  printf("jdld: dumping %ld bytes\n", chunk_size);
	  #ifdef ACTUALLY_DO_THE_SCARY_THING
	  if (chunk_size > 0) {
	    // HERE THERE BE DRAGONS
	    // we map, transfer, unmap because otherwise dow will break
	    // with a VA error (since it's mapped).
	    mbox_vptr = (uint64_t *) mmap( NULL, jtag_mailbox_size,
					   PROT_READ, MAP_SHARED,
					   memfd, 
					   jtag_mailbox);
	    if (mbox_vptr == MAP_FAILED) {
	      perror("mmap failed");
	      goto cleanup;
	    }
	    wb = write(destfd, mbox_vptr, chunk_size);
	    if (wb != chunk_size) {
	      if (wb != -1) {
		printf("jdld: only wrote %ld/%ld bytes??\n",
		       wb,
		       chunk_size);
	      } else {
		perror("jdld: write error");
		// you HAVE to continue here, you MUST munmap
	      }
	    } else {
	      printf("jdld: wrote %ld/%ld bytes\n", wb, chunk_size);
	    }
	    munmap(mbox_vptr, jtag_mailbox_size);
	    // END HERE THERE BE DRAGONS
	  }
	  #endif
	  // note: this means if it's exactly a multiple of 1MB you
	  // don't end with D 1048576, you do D\n, then end with D 0\n
	  // I think this is fine since in jdownload you read 1MB at a
	  // time, and so the last read will be empty since you're at EOF
	  // but the previous one will still return OK.
	  if (chunk_size != jtag_mailbox_size) {
	    close(destfd);
	    printf("jdld: file complete, closing\n");
	    destfd = -1;
	  }
	  if (wb == chunk_size)
	    fprintf(rsp, "K\n");
	  else
	    fprintf(rsp, "?\n");
	}
      }
      else if (lbuf[0] == 'X') {
	break;
      } else {
	printf("jdld: ???\n");
	fprintf(rsp, "?\n");
      }
    }
    fflush(stdout);
  }
  printf("jdld: exiting\n");
 cleanup:
  if (cmd != NULL) {
    fclose(cmd);
    unlink(command_fifo);
  }
  if (rsp != NULL) {
    fclose(rsp);
    unlink(response_fifo);
  }
  if (lbuf != NULL) {
    free(lbuf);
  }
  if (memfd != -1) {
    close(memfd);
  }
  if (destfd != -1) {
    close(destfd);
  }
}
