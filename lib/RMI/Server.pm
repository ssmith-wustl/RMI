#!/usr/bin/env perl

package RMI::Server;

use strict;
use warnings;
use RMI;

my @p = qw/reader writer sent received/;
sub new {
    my $class = shift;
    my $self = bless { @_ }, $class;
    for my $p (@p) {
        unless ($self->{$p}) {
            die "no $p on object!"
        }
    }
    return $self;
}

1;
