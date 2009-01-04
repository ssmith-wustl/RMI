
package RMI::Server;

# use RMI;
# my $s= RMI::Server::TcpSingleThread->new(host => '0.0.0.0', port => 10293);
# $s->start(undef);

use strict;
use warnings;
use Time::HiRes;
use base 'RMI::Node';

# go into a loop processing messages from all the connected sockets (and 
# the listen socket), for the given time period in seconds.  0 seconds
# means do one pass through all that are readable and return, undef
# means stay in the loop forever
#
# FIXME socket communication needs to be refactored out to some common location
# for example, the listen socket and client sockets can both implement
# process_message(), where the listen socket does what is accept_connection()
sub start {
    my($self,$timeout) = @_;
    my $start_time = Time::HiRes::time();
    while(1) {
        last if $self->{is_closed};
        next unless $self->_receive('query',$timeout);        
        last if(defined($timeout) && 
                    ( $timeout == 0 ||
                      (Time::HiRes::time() - $start_time > $timeout)
                    )
               );
    }
    return 1;
}

1;
