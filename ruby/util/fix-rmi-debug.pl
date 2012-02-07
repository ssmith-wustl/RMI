#!/usr/bin/perl -ni 
if (/;/) { 
    s/;//;
    s/print (.*) if \$RMI::DEBUG;/\$RMI_DEBUG && print($1)/; 
    s/RMI::DEBUG/RMI_DEBUG/g; 
    s/$RMI_DEBUG_MESSAGE_PREFIX/#{$RMI_DEBUG_MESSAGE_PREFIX}/; 
    s/\$\$/#{\$\$}/g; 
    s/\$(\w+)/\#\{$1\}/g; 
    s/my //;
    s/->/./g;
    s/use strict;//;
    s/use warnings;//;
    s/^(\s*)\}/$1end/;
    s/^sub (\w+)\s*{/def $1/;
} 
print



