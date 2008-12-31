#!/usr/bin/env perl

package RMI::Server;

use strict;
use warnings;
use RMI;

sub new {
    my $class = shift;
    my $self = bless { @_ }, $class;
}

1;
