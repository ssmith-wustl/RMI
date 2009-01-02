#!/usr/bin/env perl

package RMI::Server;

use strict;
use warnings;
use base 'RMI::Node';

sub start {
    shift->_receive('query');
}


1;
