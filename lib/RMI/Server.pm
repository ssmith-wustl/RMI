package RMI::Server;

use strict;
use warnings;
use version;
our $VERSION = qv('0.1');

use base 'RMI::Node';

# Example:
# use RMI;
# my $s= RMI::Server::Tcp->new(port => 10293);
# $s->run(undef);


sub run {
    my($self) = @_;
    while(1) {
        last if $self->{is_closed};
        next unless $self->receive_request_and_send_response();        
    }
    return 1;
}

1;
