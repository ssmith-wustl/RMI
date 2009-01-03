#!/usr/bin/env perl

package RMI::Client::Tcp;

use strict;
use warnings;
use IO::Socket;
use base 'RMI::Client';

__PACKAGE__->mk_ro_accessors(qw/host port/);

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

sub _init_created_socket {
    # override in sub-classes
    1;
}

use FreezeThaw;

sub _remote_get_with_rule {
    my $self = shift;

    my $string = FreezeThaw::freeze(\@_);
    my $socket = $self->socket;

    # First word is message length, second is command - 1 is "get"
    $socket->print(pack("LL", length($string),1),$string);

    my $cmd;
    ($string,$cmd) = $self->_read_message($socket);

    unless ($cmd == 129)  {
        $self->error_message("Got back unexpected command code.  Expected 129 got $cmd\n");
        return;
    }
      
    return unless ($string);  # An empty response
    
    my($result) = FreezeThaw::thaw($string);

    return @$result;
}
    
    
# This should be refactored into a messaging module later
sub _read_message {
    my $self = shift;
    my $socket = shift;

    my $buffer = "";
    my $read = $socket->sysread($buffer,8);
    if ($read == 0) {
        # The handle must be closed, or someone set it to non-blocking
        # and there's nothing to read
        return (undef, -1);
    }

    unless ($read == 8) {
        die "short read getting message length";
    }

    my($length,$cmd) = unpack("LL",$buffer);
    my $string = "";
    $read = $socket->sysread($string,$length);

    return($string,$cmd);
}

1;

