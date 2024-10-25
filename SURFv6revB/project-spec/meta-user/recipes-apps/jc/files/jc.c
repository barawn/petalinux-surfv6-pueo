/*
 * this is a stupid program used by jdownload
 * it opens jdld-fifo and forwards lines from stdin
 * to jdld-fifo, reads responses and prints them
 * on stdout.
 *
 * it's essentially a jdld console
 * jdld-fifo is created 0666 so this can be run as any user
 * but obviously jdld needs to be run as root.
 */

#include <sys/types.h>
#include <sys/stat.h>
#include <stdio.h>
#include <errno.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>

int main() {
  char *lbuf;
  size_t mx = 80;
  ssize_t nb;
  FILE *cmd;
  FILE *rsp;
  
  cmd = fopen("/tmp/jdld-cmd", "r+");
  if (cmd == NULL) {
    perror("jc: error opening cmd fifo");
    goto cleanup;
  }
  rsp = fopen("/tmp/jdld-rsp", "r+");
  if (rsp == NULL) {
    perror("jc: error opening rsp fifo");
    goto cleanup;
  }
  lbuf = (char *) malloc(sizeof(char)*mx);
  if (lbuf == NULL) {
    fprintf(stderr, "jc: error allocating line memory\n");
    goto cleanup;
  }
  // *everything's* line buffered, folks
  setlinebuf(stdin);
  setlinebuf(stdout);
  setlinebuf(cmd);
  setlinebuf(rsp);
  while (1) {
    nb = getline(&lbuf, &mx, stdin);
    if (nb == -1) {
      printf("jc: exiting\n");
      break;
    }
    fputs(lbuf, cmd);
    nb = getline(&lbuf, &mx, rsp);
    if (nb == -1) {
      fprintf(stderr, "jc: error reading rsp fifo\n");
      goto cleanup;
    }
    fputs(lbuf, stdout);
  }
 cleanup:
  if (lbuf != NULL) free(lbuf);
  if (cmd != NULL) fclose(cmd);
  if (rsp != NULL) fclose(rsp);
}
