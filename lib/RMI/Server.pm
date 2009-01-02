#!/usr/bin/env perl

package RMI::Server;

use strict;
use warnings;
use base 'RMI::Node';

sub start {
    my $self = shift;
    $self->_receive('query');
}


1;
