.PHONY: all clean test

PROG=   collectd-prv
SRCS=   collectd-prv.c \
        strtonum.c \
        sandbox_null.c \
        sandbox_rlimit.c \
        sandbox_seccomp.c \
        sandbox_pledge.c \
        sandbox_capsicum.c

UNAME_SYS := $(shell uname -s)
ifeq ($(UNAME_SYS), Linux)
    CFLAGS ?= -D_FORTIFY_SOURCE=2 -O2 -fstack-protector-strong \
              -Wformat -Werror=format-security \
              -fno-strict-aliasing
    LDFLAGS ?= -Wl,-z,relro,-z,now
    PRV_SANDBOX ?= seccomp
else ifeq ($(UNAME_SYS), OpenBSD)
    CFLAGS ?= -DHAVE_STRTONUM \
              -D_FORTIFY_SOURCE=2 -O2 -fstack-protector-strong \
              -Wformat -Werror=format-security \
              -fno-strict-aliasing
    LDFLAGS ?= -Wl,-z,relro,-z,now
    PRV_SANDBOX ?= pledge
else ifeq ($(UNAME_SYS), FreeBSD)
    CFLAGS ?= -DHAVE_STRTONUM \
              -D_FORTIFY_SOURCE=2 -O2 -fstack-protector-strong \
              -Wformat -Werror=format-security \
              -fno-strict-aliasing
    LDFLAGS ?= -Wl,-z,relro,-z,now
    PRV_SANDBOX ?= capsicum
endif

RM ?= rm

PRV_SANDBOX ?= rlimit
PRV_CFLAGS ?= -g -Wall -fwrapv

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
