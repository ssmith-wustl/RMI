package RMI::Server::Tcp;
use base 'RMI::Server';

use strict;
use warnings;
use version;
our $VERSION = qv('0.1');

use RMI;
use IO::Socket;
use IO::Select;
use Fcntl;

RMI::Node::_mk_ro_accessors(__PACKAGE__, qw/host port listen_socket all_select sockets_select listen_queue_size/);

sub new {
    my $class = shift;

    my $self = bless { port => 10293, @_ }, $class;
    return unless $self;

    unless ($self->listen_socket) {
        my $listen = IO::Socket::INET->new(LocalHost => $self->host,
                                           LocalPort => $self->port,
                                           Listen    => $self->listen_queue_size,
                                           ReuseAddr => 1);
        unless ($listen) {
            die "Couldn't create socket: $!";
        }
        $self->{listen_socket} = $listen;
        $self->{all_select} = IO::Select->new($listen);
        $self->{sockets_select} = IO::Select->new();
    }

    return $self;
}

# Override in the base class to delegate to whichever socket returns a value next.
# Note, that this only receives queries, since the delegate will receive all responses
# to our own counter queries.

sub receive_request_and_send_response {
    my ($self,$timeout) = @_;
    my $select = $self->all_select;
    my @ready = $select->can_read($timeout);
    for (my $i = 0; $i < @ready; $i++) {
        if ($ready[$i] eq $self->listen_socket) {
            $self->_accept_connection();
            return;
        }
        else {
            # delegate to the right "server" object, which manages just this particular client
            my $delegate_server = $self->{_server_for_socket}{$ready[$i]};
            $delegate_server->receive_request_and_send_response;
            if ($delegate_server->{is_closed}) {
                $self->_close_connection($ready[$i]);
            }
        }
    }
    return 1;
}

# Add the given socket to the list of connected clients.
# if socket is undef, it blocks waiting on an incoming connection 
sub _accept_connection {
    my $self = shift;
    my $socket = shift;

    unless ($socket) {
        my $listen = $self->listen_socket;
        $socket = $listen->accept();
        unless ($socket) {
            die "accept() failed: $!";
        }
    }

    my $server = RMI::Server->new(
        reader => $socket,
        writer => $socket,
        peer_pid => "$socket",
    );
    unless ($server) {
        die "failed to create RMI::Server for accepted socket";
    }

    $self->{_server_for_socket}{$socket} = $server;
    
    $self->sockets_select->add($socket);
    $self->all_select->add($socket);

    return $socket;
}

sub _close_connection {
    my $self = shift;
    my $socket = shift;

    unless ($self->sockets_select->exists($socket)) {
        die "Passed-in socket is not on the list of connected clients";
    }

    $self->sockets_select->remove($socket);
    $self->all_select->remove($socket);
    $socket->close();
    return 1;
}

1;
