require "rmi"
require "socket"

class RMI::Client::Tcp < RMI::Client


attr_accessor :host, :port

@@DEFAULT_HOST = "127.0.0.1"
@@DEFAULT_PORT = 4409

def initialize(*args)
    super(*args)

    if @host == nil
        @host = @@DEFAULT_HOST
    end

    if @port == nil
        @port == @DEFAULT_PORT
    end

    socket = TCPSocket.new(@host, @port)
    @reader = socket
    @writer = socket
end

=begin

=pod

=head1 NAME

RMI::Client::Tcp - an RMI::Client implementation using TCP/IP sockets

=head1 VERSION

This document describes RMI::Client::Tcp v0.11.

=head1 SYNOPSIS

    c = RMI::Client::Tcp.new(
        :host => 'myserver.com', # defaults to 'localhost'
        :port => 1234            # defaults to 4409
    )

    remote_fh = c.call_class_method('File', 'open', '/my/file', 'r');
    print remote_fh.readline
    
=head1 DESCRIPTION

This subclass of RMI::Client makes a TCP/IP socket connection to an
B<RMI::Server::Tcp>.  See B<RMI::Client> for details on the general client 
API.

See for B<RMI::Server::Tcp> for details on how to start a matching
B<RMI::Server>.

See the general B<RMI> description for an overview of how RMI::Client and
RMI::Servers interact, and examples.   

=head1 METHODS

This class overrides the constructor for a default RMI::Client to make a
socket connection.  That socket is both the reader and writer handle for the
client.

=head1 BUGS AND CAVEATS

See general bugs in B<RMI> for general system limitations of proxied objects.

=head1 SEE ALSO

B<RMI>, B<RMI::Server::Tcp>, B<RMI::Client>, B<RMI::Server>, B<RMI::Node>, B<RMI::ProxyObject>

=cut

=end

end
