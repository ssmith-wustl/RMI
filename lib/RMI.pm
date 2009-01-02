
package RMI;

use strict;
use warnings;

# the whole family
use RMI::Node;
use RMI::Client;
use RMI::Server;
use RMI::ProxyObject;
use RMI::ProxyReference;
use Data::Dumper;

# turn on debug messages
our $DEBUG;
BEGIN { $RMI::DEBUG = $ENV{RMI_DEBUG}; };

# control debug messages
our $DEBUG_INDENT = '';

# flag checked by DESTROY handlers
our $process_is_ending = 0;
sub END {
    $process_is_ending = 1;
}

1;

