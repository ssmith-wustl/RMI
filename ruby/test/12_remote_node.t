#!/usr/bin/env ruby

use strict;
use warnings;
use Test::More tests => 3;
use FindBin;
use lib $FindBin::Bin;
use Data::Dumper;
use RMI::Client::ForkedPipes;

my $c = RMI::Client::ForkedPipes->new();
ok($c, "created a test client/server pair");

my $s = $c->_remote_node;
my $r = ref($s);
is($r,'RMI::Proxy::RMI::Server::ForkedPipes', 'remote node has the expected class');

my $rr = $s->_remote_node;
is($rr,$c,"the remote node's remote node is us");

