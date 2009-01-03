#!/usr/bin/env perl

use strict;
use warnings;
use Test::More tests => 10;
use RMI::TestClass2;

sub local_exception { die 'local exception'; }

use_ok("RMI::Client");
my $c = RMI::Client->new();
ok($c, "created an RMI::Client using the default constructor (fored process with a pair of pipes connected to it)");

my $remote1 = $c->call_class_method('RMI::TestClass2', 'new', name => 'remote1');
ok($remote1, "got a remote object");

eval { local_exception(1,2,3) };
ok($@,'generated local exception');
ok($@ =~ /local exception/, "exception is correct") or diag($@);

eval { $c->remote_eval("die 'remote exception'"); };
ok($@,'generated a remote exception!');
ok($@ =~ /remote exception/, "exception is correct") or diag($@);

eval { $c->call_function('main::local_exception',1,2,3) };
ok($@,'generated a local exception during a remote function call exception');
ok($@ =~ /local exception/, "exception is correct") or diag($@);

ok($c->close, "closed the client connection");
exit;
