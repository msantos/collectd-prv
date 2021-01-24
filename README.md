collectd-prv: stdout to collectd notifcations
=============================================

collectd-prv converts stdout from a process into collectd notifications,
optionally acting like a pressure relief valve during event floods.

Usage
-----

Example
-------

* script

~~~ collectd-tail
#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

# plugin = tail
# type = syslog
# limit = 30 lines/second
tail -F $1 | collectd-prv --service="tail/syslog" --limit=30
~~~

~~~ collectd.conf
LoadPlugin exec
<Plugin exec>
  Exec "nobody:nobody" "collectd-tail" "/var/log/syslog"
</Plugin>
~~~

Build
-----

    make

    # Recommended: build a static executable using musl
    ./musl-make clean all

    # select a different method for process restriction
    RESTRICT_PROCESS=null

    # musl: enabling seccomp process restriction might require downloading a
    # copy of linux kernel headers
    MUSL_INCLUDE=/tmp

    cd $MUSL_INCLUDE
    git clone https://github.com/sabotage-linux/kernel-headers.git

    ./musl-make

Process Restrictions
--------------------

Options
-------

-s, --service *plugin*/*type*
:		collectd service (default: stdout/prv)

-H, --hostname *name*
:		collectd hostname (max: 16 bytes) (default: gethostname())

-l, --limit *number*
:		message rate limit (default: 0 (no limit))

-w, --window *seconds*
:		message rate window (default: 1 second)

-W, --write-error *exit|drop|block*
:		behaviour if write buffer is full

-M, --max-event-length *number*
:		max message fragment length (default: 255 - 10)

-I, --max-event-id *number*
:		max message fragment header id (default: 99)

-v, --verbose
:		verbose mode

-h, --help
:		help

Examples
--------

TODO
----
