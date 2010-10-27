#!/usr/bin/env perl

use strict;
use warnings;
use Test::More tests => 1;
use FindBin;
use lib $FindBin::Bin;
use Data::Dumper;
use RMI::Client::ForkedPipes;

my $c = RMI::Client::ForkedPipes->new();
ok($c, "created a test client/server pair");


