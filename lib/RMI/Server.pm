package RMI::Server;

use strict;
use warnings;
use version;
our $VERSION = qv('0.1');

use base 'RMI::Node';

sub run {
    my($self) = @_;
    while(1) {
        last if $self->{is_closed}; 
        last unless $self->receive_request_and_send_response();
    }
    return 1;
}

1;

=pod

=head1 NAME

RMI::Server - service remote RMI requests

=head1 SYNOPSIS

    $s = RMI::Server->new(
        reader => $fh1,
        writer => $fh2,
    );
    $s->run;

    $s = RMI::Server::Tcp->new(
        port => 1234
    );
    $s->run;

    $s = RMI::Server->new(...);
    for (1..3) {
        $s->receive_request_and_send_response;
    }
    
=head1 DESCRIPTION

This is the base class for RMI::Servers, which accept requests
for on an IO handle of some sort, execute code on behalf of the
request, and send the return value back to the client.

When the RMI::Server responds to a request which returns objects or references,
the items in question are not serialized back to the client.  Instead the client
recieves an identifier, and creates a proxy object which uses the client
to delegate method calls to its counterpart on the server.

When objects or refrences are sent to an RMI server as parameters, the server
creates a proxy to represent them, and the client in effect becomes the
server for those proxy objects.  The real reference stays on the client,
and all interaction with the item in question during the invocation
result in counter-requests being sent back to the client for method
resolution on that end.

See the detailed explanation of remote proxy references in the B<RMI> module.

=back

=head1 METHODS

=item new(reader => $fh1, writer => $fh2)

This is typically overriden in a specific subclass of RMI::Server to construct
the reader and writer according to a particular strategy.  It is possible for
the reader and the writer to be the same handle, particularly for RMI::Server::Tcp.

=head1 BUGS AND CAVEATS

See general bugs in B<RMI> for general system limitations

=head1 SEE ALSO

B<RMI> B<RMI::Node> B<RMI::Client> B<RMI::Server::Tcp> B<RMI::Server::ForkedPipes>

=cut
