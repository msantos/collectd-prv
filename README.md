# collectd-prv: stdout to collectd notifications

collectd-prv converts stdout from a process into collectd notifications,
optionally acting like a pressure relief valve during event floods.

## Usage

## Example

* collectd-tail

```bash
#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

# plugin = tail
# type = syslog
# limit = 30 lines/second
tail -F $1 | collectd-prv --service="tail/syslog" --limit=30
```

* collectd.conf

```bash
LoadPlugin exec
<Plugin exec>
  Exec "nobody:nobody" "collectd-tail" "/var/log/syslog"
</Plugin>
```

## Build

```bash
make

# Recommended: build a static executable using musl
## sudo apt install musl-dev musl-tools
./musl-make clean all

# select a different method for process restriction
RESTRICT_PROCESS=null make clean all

# musl: enabling seccomp process restriction requires downloading linux
# kernel headers
export MUSL_INCLUDE=/tmp
git clone https://github.com/sabotage-linux/kernel-headers.git $MUSL_INCLUDE/kernel-headers
./musl-make
```

## Options

-s, --service *plugin*/*type*
: collectd service (default: stdout/prv)

-H, --hostname *name*
: collectd hostname (max: 16 bytes) (default: gethostname())

-l, --limit *number*
: message rate limit (default: 0 (no limit))

-w, --window *seconds*
: message rate window (default: 1 second)

-W, --write-error *exit|drop|block*
: behaviour if write buffer is full

-M, --max-event-length *number*
: max message fragment length (default: 255 - 10)

-I, --max-event-id *number*
: max message fragment header id (default: 99)

-v, --verbose
: verbose mode

-h, --help
:  help
