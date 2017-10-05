.PHONY: all clean test

PROG=   collectd-prv
SRCS=   collectd-prv.c \
        sandbox_null.c \
        sandbox_rlimit.c \
        sandbox_seccomp.c

UNAME_SYS := $(shell uname -s)
ifeq ($(UNAME_SYS), Linux)
    CFLAGS ?= -D_FORTIFY_SOURCE=2 -O2 -fstack-protector \
              --param=ssp-buffer-size=4 -Wformat -Werror=format-security \
              -fno-strict-aliasing
	PRV_SANDBOX ?= seccomp
else ifeq ($(UNAME_SYS), OpenBSD)
    CFLAGS ?= -D_FORTIFY_SOURCE=2 -O2 -fstack-protector \
              --param=ssp-buffer-size=4 -Wformat -Werror=format-security \
              -fno-strict-aliasing
else ifeq ($(UNAME_SYS), FreeBSD)
    CFLAGS ?= -D_FORTIFY_SOURCE=2 -O2 -fstack-protector \
              --param=ssp-buffer-size=4 -Wformat -Werror=format-security \
              -fno-strict-aliasing
endif

RM ?= rm

PRV_SANDBOX ?= rlimit
PRV_CFLAGS ?= -g -Wall

CFLAGS += $(PRV_CFLAGS) \
		  -DPRV_SANDBOX=\"$(PRV_SANDBOX)\" -DPRV_SANDBOX_$(PRV_SANDBOX)

LDFLAGS += $(PRV_LDFLAGS)

all: $(PROG)

$(PROG):
	$(CC) $(CFLAGS) -o $(PROG) $(SRCS) $(LDFLAGS)

clean:
	-@$(RM) $(PROG)

test: $(PROG)
	@PATH=.:$(PATH) bats test
