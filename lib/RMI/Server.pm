
package RMI::Server;

# use RMI;
# my $s= RMI::Server::TcpSingleThread->new(host => '0.0.0.0', port => 10293);
# $s->start(undef);

use strict;
use warnings;
use base 'RMI::Node';

sub start {
    my $self = shift;
    $self->_receive('query',0);
}

sub process_message {
    my $self = shift;
    $self->_receive('query',1);
}

1;
