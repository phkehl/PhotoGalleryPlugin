#!/bin/sh
tail -F \
     /home/flip/git/foswiki-dev/core/working/logs/events.log \
     /home/flip/git/foswiki-dev/core/working/logs/debug.log \
     /home/flip/git/foswiki-dev/core/working/logs/error.log \
    | awk '/^==>/ { gsub("^.*/", "", $2); f=$2; getline; } ! /^$/ { print "\033[36m"f"\033[m "$0 }'
