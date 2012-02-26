#!/usr/bin/perl -ni 
if (/;/ or s/ eq / == /g) { 
    s/\$self\-\>\{(\w+)\}/\@\1/g;
    s/print (.*) if \$RMI::DEBUG;/\$RMI_DEBUG && print($1)/; 
    s/RMI::DEBUG/RMI_DEBUG/g; 
    s/\$RMI_DEBUG_MESSAGE_PREFIX/#{\$RMI_DEBUG_MESSAGE_PREFIX}/; 
    s/\$\$/#{\$\$}/g; 
    s/\@//g;
    #s/\$(\w+)/\#\{$1\}/g; 
    s/my [\$\@\%]//;
    s/my //;
    s/->/./g;
    s/(use|no) strict;//;
    s/(use|no) warnings;//;
    s/\$//g unless /\$RMI_/;
    s/(shift|pop) (\S+)/\2\.\1/;
    s/ \. / + /g;
    s/;//;
}
s/^\s*sub\s*(\S+)\s*\{/def $1/;
s/^(\s*)(if|unless|while|elsif)\s*\((.*)\)\s*\{(\s*)/$1$2 ($3)$4/
 and s/\$//g;
s/^(\s*)(else)(\s*)\{(\s*)/$1$2$3$4/ 
 and s/\$//g;
s/^\s*\(self\)\s*\=\s*\@\_\s*$//;
#s/^(\s*)\}(\s*)/$1end$2/;
s/^\}(\s*)/end$1/;
print

