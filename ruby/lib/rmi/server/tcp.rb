require "rmi"
require "socket"

@@DEFAULT_PORT = 4409;

class RMI::Server::Tcp < RMI::Server

attr_accessor :host, :port, :listen_socket, :all_select, :sockets_select, :listen_queue_size

def initialize(*args)
    super(*args)
    if @port == nil
        @port = @@DEFAULT_PORT
    end
    @listen_socket = TCPServer.new(@port)
    @client_sockets = []
    @server_for_client_socket = {}
end


def receive_request_and_send_response(timeout=1000)
    readable, writable = IO.select([@listen_socket] + @client_sockets)
    readable.each do |s|
        begin
            if s == @listen_socket
                new_socket = @listen_socket.accept_nonblock
                @client_sockets.push(new_socket)
                node = RMI::Node.new(
                    :reader => new_socket,
                    :writer => new_socket
                )
                @server_for_client_socket[new_socket] = node
                print "opening non-blocking socket #{new_socket} and rmi node #{node} for new connection\n"
            else
                delegate_server = @server_for_client_socket[s]
                retval = delegate_server.receive_request_and_send_response
                if retval == nil
                    # connection closed
                    @client_sockets.delete_if { |sx| sx == s }
                    print "closing #{s}, tossing #{delegate_server}\n"
                    @server_for_client_socket.delete(s)
                    return nil
                else
                    print "message on #{s} for #{delegate_server}\n"
                    return retval
                end
            end
        rescue Errno::EAGAIN, Errno::EWOULDBLOCK
        end
    end
    # we only get here if NOTHING is readable
    return nil
end


=begin
def _close_connection
    # This is no longer called, and somehow the select sockets get things removed?
    my $self = shift;
    my $socket = shift;

    unless ($self->sockets_select->exists($socket)) {
        warn ("Passed-in socket $socket is not on the list of connected clients");
    }
    unless ($self->all_select->exists($socket)) {
        warn ("Passed-in socket $socket is not on the list of all clients");
    }
    print "removed $socket\n";

    $self->sockets_select->remove($socket);
    $self->all_select->remove($socket);
    $socket->close();
    return 1;
end
                buf = @buffer_for_socket[s] ||= ''
                buf << s.read_nonblock(1024)
                if buf =~ /^.*?\r?\n/
                    client.write
                    client.close
                end
    # the list of all sockets w/ data ready
    my $data_ready = $self->{data_ready};
    
    # ck for new connections and also new sockets with data
    my $select = $self->all_select;
    until (@$data_ready) {
        my @new_readable = $select->can_read($timeout);
        unless (@new_readable) {
            return;
        }
        my @new_data;
        for (my $i = 0; $i < @new_readable; $i++) {
            if ($new_readable[$i] eq $self->listen_socket) {
                $self->_accept_connection();;
            }
            else {
                push @new_data, $new_readable[$i]
            }
        }
        push @$data_ready, @new_data;
    }
    
    # process the first socket with data
    # delegate to the right "server" object, which manages just this particular client
    my $ready = shift @$data_ready;
    my $delegate_server = $self->{_server_for_socket}{$ready};
    my $retval = $delegate_server->receive_request_and_send_response;    
    return $retval;
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
        peer_id => "$socket",
    );
    unless ($server) {
        die "failed to create RMI::Server for accepted socket";
    }

    $self->{_server_for_socket}{$socket} = $server;
    
    $self->sockets_select->add($socket);
    $self->all_select->add($socket);
    return $socket;
}

sub new {
    my $class = shift;

    my $self = bless { port => $DEFAULT_PORT, @_ }, $class;
    return unless $self;

    unless ($self->listen_socket) {
        my $listen = IO::Socket::INET->new(
            LocalHost => $self->host,
            LocalPort => $self->port,
            ReuseAddr => 1,
            Listen    => $self->listen_queue_size,
        );
        unless ($listen) {
            die "Couldn't create socket: $!";
        }
        $self->{listen_socket} = $listen;
        $self->{all_select} = IO::Select->new($listen);
        $self->{sockets_select} = IO::Select->new();
        $self->{data_ready} = [];
    }

    return $self;
}

# Override in the base class to delegate to whichever socket returns a value next.
# Note, that this only receives queries, since the delegate will receive all responses
# to our own counter queries.


1;


=pod

=head1 NAME

RMI::Server::Tcp - service RMI::Client::Tcp requests

=head1 VERSION

This document describes RMI::Server::Tcp v0.11.

=head1 SYNOPSIS

    $s = RMI::Server::Tcp->new(
        port => 1234            # defaults to 4409
    );
    $s->run;
    
=head1 DESCRIPTION

This subclass of RMI::Server makes a TCP/IP listening socket, and accepts
multiple non-blocking IO connections.

=head1 METHODS

This class overrides the constructor for a default RMI::Server to make a
listening socket.  Individual accepted connections get their own private
subordinate RMI::Server of this class.

=head1 BUGS AND CAVEATS

See general bugs in B<RMI> for general system limitations of proxied objects.

=head1 SEE ALSO

B<RMI>, B<RMI::Client::Tcp>, B<RMI::Client>, B<RMI::Server>, B<RMI::Node>, B<RMI::ProxyObject>

=cut

=end

end

