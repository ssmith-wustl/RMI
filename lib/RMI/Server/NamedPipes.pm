#!/usr/bin/env perl

package RMI::Server::NamedPipes;

use strict;
use warnings;
use base 'RMI::Server';
use IO::File;     
use RMI::Client::NamedPipes;

*new = \&RMI::Client::NamedPipes::new;

1;

