#!/usr/bin/env bash 
perl -ni -e 'if (/RMI::DEBUG/) { s/print (.*) if \$RMI::DEBUG;/\$RMI_DEBUG && print($1)/; s/RMI::DEBUG/RMI_DEBUG/g; s/$RMI_DEBUG_MESSAGE_PREFIX/#{$RMI_DEBUG_MESSAGE_PREFIX}/; s/\$\$/#{\$\$}/; s/\$(\w+)/\#\{$1\}/; } print' $*

grep DEBUG $*


