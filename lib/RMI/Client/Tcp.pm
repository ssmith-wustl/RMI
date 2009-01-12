#!/usr/bin/env perl

package RMI::Client::Tcp;

use strict;
use warnings;
use IO::Socket;
use base 'RMI::Client';

RMI::Node::mk_ro_accessors(__PACKAGE__, qw/host port/);

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(host => "127.0.0.1", port => 10293, reader => 1, writer => 1, @_);
    return unless $self;

    my $socket = IO::Socket::INET->new(PeerHost => $self->host,
                                       PeerPort => $self->port,
                                       ReuseAddr => 1,
                                       #ReusePort => 1,
                                     );
    unless ($socket) {
        my $msg = sprintf("Failed to connect to remote host %s:%s : $!",
                                      $self->host, $self->port);
        $self = undef;
        die $msg;
    }

    $self->{reader} = $socket;
    $self->{writer} = $socket;

    return $self;
}

1;

