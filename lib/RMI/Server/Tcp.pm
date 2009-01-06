
package RMI::Server::Tcp;
use base 'RMI::Server';

use strict;
use warnings;
use IO::Socket;
use IO::Select;
use FreezeThaw;
use Fcntl;
use RMI;

RMI::Node::mk_ro_accessors(__PACKAGE__, qw/host port listen_socket all_select sockets_select use_sigio listen_queue_size/);

sub new {
    my $class = shift;

    my $self = bless { port => 10293, @_ }, $class;
    return unless $self;
    return $self if ($self->listen_socket);

    unless ($self->listen_socket) {
        unless ($self->_create_listen_socket()) {
            die "Failed to create listen socket!";
        }        
    }

    $self->enable_sigio_processing(1) if ($self->use_sigio);

    return $self;
}

sub _create_listen_socket {
    my $self = shift;
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
    return 1;
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
            # If we're running as a signal handler for sigio, and the client has already sent
            # data down the newly-connected socket before we can leave the handler, then we've
            # already lost the signal for that new data since it was masked.  This workaround
            # gives the above select() a chance to see the data being ready.
            #next SELECT_LOOP;
            return;
        } else {
            # delegate to the right "server" object, which manages just this particular client
            my $delegate_server = $self->{_server_for_socket}{$ready[$i]};
            $delegate_server->receive_request_and_send_response;
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
    $self->_enable_async_io_on_handle($socket) if ($self->use_sigio);

    return $socket;
}

sub _close_connection {
    my $self = shift;
    my $socket = shift;

    unless ($self->sockets_select->exists($socket)) {
        die "Passed-in socket is not on the list of connected clients";
    }

    $self->_disable_async_io_on_handle($socket) if ($self->use_sigio);
    $self->sockets_select->remove($socket);
    $self->all_select->remove($socket);
    $socket->close();
    return 1;
}

# FIXME There's a more efficient method of determining which handles 
# need attention during a sigio than select()ing.  See the manpage of
# fcntl(2) and the section on F_SETSIG and setting SA_SIGINFO.  Implement
# this later
# FIXME there should probably be a way to turn it off, too
sub enable_sigio_processing {
    my $self = shift;

    $self->use_sigio(1);
    my $prev_sigio_handler = $SIG{'IO'};
    
    # Step 1, set the closure for handling the signal
    $SIG{'IO'} = sub {
        $self->start(0);
        return unless $prev_sigio_handler;
        $prev_sigio_handler->();
    };

    # Set up async IO stuff on all the active handles
    foreach my $fh ( $self->all_select->handles ) {
        $self->_enable_async_io_on_handle($fh);
    }
}

sub _enable_async_io_on_handle {
    my($self,$fh) = @_;

    # Set the pid for processing the signal (that would be us)
    # At one point, there was a bug in fcntl that could cause it to die
    # with a "Modification of a read-only value attempted" exception
    # if the F_SETOWN was right in fcntl()'s arg list.  I don't know if
    # or when the bug was fixed, but the workaround is to copy the constant
    # value into a mutable scalar first
    my $getowner = &Fcntl::F_GETOWN;
    my $prev_owner = fcntl($fh, $getowner,0);

    my $setowner = &Fcntl::F_SETOWN;
    #my $pid = $$;
    #$pid += 0;   # if $$ was ever used in string context, fcntl does the wrong thing with it.  This forces it back to numberic context
    unless (fcntl($fh, $setowner, $$ + 0)) {
        die "fcntl F_SETOWN failed: $!";
    }

#    my $setsig = &Fcntl::F_SETSIG;
#    my $signum = 100;
#    unless (fcntl($fh, $setsig, $signum)) {
#       $self->error_message("fcntl F_SETSIG failed: $!");
#       return;
#    }

    # Enable the async IO flag
    my $flags = fcntl($fh, &Fcntl::F_GETFL,0);
    unless ($flags) {
        fcntl($fh, $setowner, $prev_owner);
        die "fcntl F_GETFL failed: $!";
    }
    $flags |= &Fcntl::O_ASYNC;
    unless (fcntl($fh, &Fcntl::F_SETFL, $flags)) {
        fcntl($fh, $setowner, $prev_owner);
        die "fcntl F_SETFL failed: $!";
    }

    return 1;
}

# This needs to be called when a handle closes or it'll generate an endless stream
# of signals to let us know that it's closed
sub _disable_async_io_on_handle {
    my($self,$fh) = @_;

    # I think it's good enough it just turn off the async flag, and not
    # have to reset the FH's owner
    my $flags = fcntl($fh, &Fcntl::F_GETFL,0);
    unless ($flags) {
        die "fcntl F_GETFL failed: $!";
    }

    $flags &= ~(&Fcntl::O_ASYNC);
    unless (fcntl($fh, &Fcntl::F_SETFL, $flags)) {
        die "fcntl F_SETFL failed: $!";
    }

    return 1;
}


# TODO: mine this logic out and improve the basic way RMI::Node works
# process a message on the indicated socket.  If socket is undef,
# then process a single message out of the many that may be ready
# to read
sub XXXprocess_message_from_client {
    my($self, $socket) = @_;

    # FIXME this always picks the first in the list; it's not fair
    $socket ||= ($self->sockets_select->can_read())[0];
    return unless $socket;

    my($string,$cmd) = UR::DataSource::RemoteCache::_read_message(undef, $socket);
    if ($cmd == -1) {  # The other end closed the socket
        $self->close_connection($socket);
        return 1;
    }

    # We only support get() for now - cmd == 1
    my($return_command_value, @results);

    if ($cmd == 1)  {
        my $rule = (FreezeThaw::thaw($string))[0]->[0];
        my $class = $rule->subject_class_name();
        @results = $class->get($rule);

        $return_command_value = $cmd | 128;  # High bit set means a result code
    } else {
        $self->error_message("Unknown command request ID $cmd");
        $return_command_value = 255;
    }
        
    my $encoded = '';
    if (@results) {
        $encoded = FreezeThaw::freeze(\@results);
    }
    $socket->print(pack("LL", length($encoded), $return_command_value), $encoded);

    return 1;
}

1;
