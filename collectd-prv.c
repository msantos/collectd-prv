/* Copyright (c) 2017-2020, Michael Santos <michael.santos@gmail.com>
 *
 * Permission to use, copy, modify, and/or distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <err.h>
#include <getopt.h>
#include <sys/param.h>
#include <time.h>

#include <errno.h>
#include <fcntl.h>

#ifndef HAVE_STRTONUM
#include "strtonum.h"
#endif
#include "restrict_process.h"

#ifdef CLOCK_MONOTONIC_COARSE
#define PRV_CLOCK_MONOTONIC CLOCK_MONOTONIC_COARSE
#else
#define PRV_CLOCK_MONOTONIC CLOCK_MONOTONIC
#endif

#define PRV_VERSION "0.5.0"

#ifndef PRV_MAXBUF
#define PRV_MAXBUF 8192
#endif

#define DATA_MAX_LEN 64

enum { PRV_WR_BLOCK = 0, PRV_WR_DROP, PRV_WR_EXIT };

typedef struct {
  int verbose;
  size_t limit;
  size_t count;
  size_t frag;
  int window;
  struct timespec t0;
  char hostname[16];
  char plugin[DATA_MAX_LEN];
  char type[DATA_MAX_LEN];
  size_t maxlen;
  size_t maxid;
  int write_error;
} prv_state_t;

static int prv_input(prv_state_t *s);
static int prv_output(prv_state_t *s, char *buf, size_t buflen);
static int prv_notify(prv_state_t *s, time_t t, int offset, size_t total,
                      char *buf, size_t n);
static int prv_notify_escape(prv_state_t *s, char *buf, size_t n);
static void *prv_calloc(size_t nmemb, size_t size);
static void usage(void);

extern char *__progname;

#define VERBOSE(__s, __n, ...)                                                 \
  do {                                                                         \
    if (__s->verbose >= __n) {                                                 \
      (void)fprintf(stderr, __VA_ARGS__);                                      \
    }                                                                          \
  } while (0)

static const struct option long_options[] = {
    {"collectd", required_argument, NULL, 'C'},
    {"service", required_argument, NULL, 's'},
    {"hostname", required_argument, NULL, 'H'},
    {"limit", required_argument, NULL, 'l'},
    {"discard", required_argument, NULL, 'd'},
    {"max-event-length", required_argument, NULL, 'M'},
    {"max-event-id", required_argument, NULL, 'I'},
    {"window", required_argument, NULL, 'w'},
    {"write-error", required_argument, NULL, 'W'},
    {"verbose", no_argument, NULL, 'v'},
    {"help", no_argument, NULL, 'h'},
    {NULL, 0, NULL, 0}};

int main(int argc, char *argv[]) {
  int ch = 0;
  prv_state_t *s = NULL;

  if (restrict_process_init() < 0)
    err(3, "restrict_process_init");

  s = prv_calloc(1, sizeof(prv_state_t));

  s->window = 1;

  s->maxid = 99;
  /* @99:99:99@ */
  s->maxlen = 255 - 10;

  if (setvbuf(stdout, NULL, _IOLBF, 0) < 0)
    err(EXIT_FAILURE, "setvbuf");

  while ((ch = getopt_long(argc, argv, "C:d:l:hH:I:M:s:w:W:v", long_options,
                           NULL)) != -1) {
    switch (ch) {
    case 's':
    case 'C': {
      char *p = NULL;

      p = strchr(optarg, '/');
      if (p == NULL)
        errx(EXIT_FAILURE, "invalid format: <plugin>/<type>: %s", optarg);

      (void)snprintf(s->plugin, sizeof(s->plugin), "%.*s",
                     (int)MIN(p - optarg, DATA_MAX_LEN - 1), optarg);
      (void)snprintf(s->type, sizeof(s->type), "%.*s",
                     (int)MIN(strlen(p + 1), DATA_MAX_LEN - 1), p + 1);
    }

    break;
    case 'd':
    case 'l':
      s->limit = strtonum(optarg, 0, 0xffff, NULL);
      if (errno)
        err(EXIT_FAILURE, "strtonum");
      break;
    case 'w':
      s->window = strtonum(optarg, 1, 0xffff, NULL);
      if (errno)
        err(EXIT_FAILURE, "strtonum");
      break;
    case 'W':
      if (strcmp(optarg, "block") == 0)
        s->write_error = PRV_WR_BLOCK;
      else if (strcmp(optarg, "drop") == 0)
        s->write_error = PRV_WR_DROP;
      else if (strcmp(optarg, "exit") == 0)
        s->write_error = PRV_WR_EXIT;
      else
        errx(EXIT_FAILURE, "invalid option: %s: block|drop|exit", optarg);

      break;
    case 'H':
      (void)snprintf(s->hostname, sizeof(s->hostname), "%.*s",
                     (int)MIN(strlen(optarg), sizeof(s->hostname) - 1), optarg);
      break;
    case 'I':
      s->maxid = strtonum(optarg, 0, 0xffff, NULL);
      if (errno)
        err(EXIT_FAILURE, "strtonum");
      break;
    case 'M':
      s->maxlen = strtonum(optarg, 0, 0xffff, NULL);
      if (errno)
        err(EXIT_FAILURE, "strtonum");
      break;
    case 'v':
      s->verbose += 1;
      break;
    case 'h':
    default:
      usage();
    }
  }

  if (s->write_error != PRV_WR_BLOCK &&
      fcntl(fileno(stdout), F_SETFL, O_NONBLOCK) < 0)
    err(EXIT_FAILURE, "fcntl");

  if ((s->hostname[0] == '\0') &&
      (gethostname(s->hostname, sizeof(s->hostname) - 1) < 0))
    err(EXIT_FAILURE, "gethostname");

  if (s->plugin[0] == '\0')
    (void)memcpy(s->plugin, "stdout", 6);

  if (s->type[0] == '\0')
    (void)memcpy(s->type, "prv", 3);

  if (clock_gettime(PRV_CLOCK_MONOTONIC, &(s->t0)) < 0)
    err(EXIT_FAILURE, "clock_gettime(CLOCK_MONOTONIC)");

  if (restrict_process_stdin() < 0)
    err(3, "restrict_process_stdin");

  if (prv_input(s) < 0)
    err(111, "prv_intput");

  exit(0);
}

static int prv_input(prv_state_t *s) {
  char buf[PRV_MAXBUF] = {0};

  while (fgets(buf, sizeof(buf), stdin) != NULL) {
    if (prv_output(s, buf, strlen(buf)) < 0) {
      if (errno == EAGAIN) {
        VERBOSE(s, 1, "PIPE FULL:dropped:%s", buf);
        if (s->write_error == PRV_WR_DROP)
          continue;
      }
      return -1;
    }
  }

  return 0;
}

static int prv_output(prv_state_t *s, char *buf, size_t buflen) {
  struct timespec t1 = {0};
  time_t t;
  int sec = 0;
  size_t chunks;
  size_t n;
  ssize_t rem;

  if (buflen == 0)
    return 0;

  if (clock_gettime(PRV_CLOCK_MONOTONIC, &t1) < 0)
    err(EXIT_FAILURE, "clock_gettime(CLOCK_MONOTONIC)");

  sec = t1.tv_sec - s->t0.tv_sec;

  if (sec >= s->window) {
    s->count = 0;
    s->t0.tv_sec = t1.tv_sec;
    s->t0.tv_nsec = 0;
  }

  VERBOSE(s, 3, "INTERVAL:%d/%d\n", sec, s->window);

  if ((s->limit > 0) && (s->count >= s->limit)) {
    VERBOSE(s, 2, "DISCARD:%zu/%zu:%s", s->count, s->limit, buf);
    return 0;
  }

  /* Don't include trailing newline */
  if (buf[buflen - 1] == '\n')
    buflen--;

  if (buflen == 0)
    return 0;

  /* number of fragments: 0 or > 0 */
  chunks = buflen / s->maxlen;

  /* length of trailing partial fragment */
  rem = buflen % s->maxlen;

  /* number of messages: 1 or > 1 */
  n = chunks + (rem == 0 ? 0 : 1);

  s->count += n;

  if ((s->limit > 0) && (s->count > s->limit)) {
    VERBOSE(s, 2, "FRAGLIMIT:count=%zu/limit=%zu/frags=%zu/rem=%zu:%s",
            s->count, s->limit, n, rem, buf);
    return 0;
  }

  t = time(NULL);

  switch (n) {
  case 1:
    if (prv_notify(s, t, 1, 1, buf, buflen) < 0)
      return -1;
    break;

  default: {
    size_t i;

    s->frag = (s->frag % s->maxid) + 1;

    for (i = 0; i < chunks; i++) {
      char *frag = buf + (s->maxlen * i);
      int fraglen = MIN(strlen(frag), s->maxlen);

      if (prv_notify(s, t, i + 1, n, frag, fraglen) < 0)
        return -1;

      s->count++;
    }

    if (rem > 0) {
      if (prv_notify(s, t, n, n, buf + (s->maxlen * (n - 1)), rem) < 0)
        return -1;

      s->count++;
    }
  }

  break;
  }

  return n;
}

static int prv_notify(prv_state_t *s, time_t t, int offset, size_t total,
                      char *buf, size_t n) {
  if (fprintf(stdout,
              "PUTNOTIF host=%s severity=okay time=%lld plugin=%s "
              "type=%s message=\"",
              s->hostname, (long long)t, s->plugin, s->type) < 0)
    return -1;

  if (total > 1) {
    if (fprintf(stdout, "@%zu:%d:%zu@", s->frag, offset, total) < 0)
      return -1;
  }

  if (prv_notify_escape(s, buf, n) < 0)
    return -1;

  if (fprintf(stdout, "\"\n") < 0)
    return -1;

  return 0;
}

static int prv_notify_escape(prv_state_t *s, char *buf, size_t n) {
  size_t i;

  for (i = 0; i < n; i++) {
    switch (buf[i]) {
    case '"':
      if (fprintf(stdout, "\\\"") < 0)
        return -1;
      break;
    case '\\':
      if (fprintf(stdout, "\\\\") < 0)
        return -1;
      break;
    default:
      if (fprintf(stdout, "%c", buf[i]) < 0)
        return -1;
      break;
    }
  }

  return 0;
}

static void *prv_calloc(size_t nmemb, size_t size) {
  char *buf = NULL;

  buf = calloc(nmemb, size);
  if (buf == NULL)
    err(EXIT_FAILURE, "calloc");

  return buf;
}

static void usage() {
  errx(EXIT_FAILURE,
       "[OPTION] <COMMAND> <...>\n"
       "Pressure relief valve, version: %s (using %s mode process "
       "restriction)\n\n"
       "-s, --service <plugin>/<type>\n"
       "                          collectd service\n"
       "-h, --hostname <name>     system hostname\n"
       "-l, --limit               message rate limit\n"
       "-w, --window              message rate window\n"
       "-W, --write-error <exit|drop|block>\n"
       "                          behaviour if write buffer is full\n"
       "-M, --max-event-length    max message fragment length\n"
       "-I, --max-event-id        max message fragment header id\n"
       "-v, --verbose             verbose mode\n"
       "-h, --help                help",
       PRV_VERSION, RESTRICT_PROCESS);
}
