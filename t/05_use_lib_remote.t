#!/usr/bin/env perl

use strict;
use warnings;
use Test::More tests => 10;
use IO::File;

# $c = RMI::Client->new();
# $c->use_remote("DBI");
#
# $c = DBI->connect(); # DBI is not really here...

my @matches;

use_ok("RMI::Client");
my $c = RMI::Client->new();
ok($c, "created an RMI::Client using the default constructor (fored process with a pair of pipes connected to it)");

ok(!RMI::TestClass1->can("new"), "test class has NOT been used before we proxy it");

eval "use lib \$c->virtual_lib";
ok(!$@, 'added a virtual lib to the @INC list which will make all attempts to use modules auto-proxy.');

use_ok("RMI::TestClass1");

my $remote2 = RMI::TestClass1->new(name => 'remote2');
ok($remote2, "created a remote object using regular/local syntax");
ok($remote2->UNIVERSAL::isa("RMI::ProxyObject"), "real class on remote object is a proxy object");
isa_ok($remote2,"RMI::TestClass1", "isa returns true when used with the proxied class");

is($remote2->m1, $c->peer_pid, "object method returns a value indicating it ran in the other process");
ok($remote2->m1 != $$, "object method returns a value indicating it did not run in this process");

use_ok("Sys::Hostname");
ok(Sys::Hostname::hostname(), "got hostname");

ok($c->close, "closed the client connection");
exit;
