
package RMI;

use strict;
use warnings;

use RMI::Node;
use RMI::Client;
use RMI::Server;
use RMI::ProxyObject;

use Data::Dumper;

BEGIN { $RMI::DEBUG = $ENV{RMI_DEBUG}; };
our $DEBUG_INDENT = '';
our $DEBUG;

1;

