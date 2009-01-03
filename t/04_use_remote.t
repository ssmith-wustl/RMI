#!/usr/bin/env perl

use strict;
use warnings;
use Test::More tests => 16;
use IO::File;

# $c = RMI::Client->new();
# $c->use_remote("DBI");
#
# $c = DBI->connect(); # DBI is not really here...

my @matches;

use_ok("RMI::Client");
my $c = RMI::Client->new();
ok($c, "created an RMI::Client using the default constructor (fored process with a pair of pipes connected to it)");

eval { $c->use_remote("IO::File") };
ok($@, "correctly failed to proxy a package which is already in use.");

ok(!RMI::TestClass1->can("new"), "test class has not been used before we proxy it");

@matches = grep { /RMI\/TestClass1/ } keys %INC;
ok(!@matches, "the test class has never been used in this process");
          
eval { $c->use_remote("RMI::TestClass1"); };
ok(!$@, "*** test class now chas been proxied!! ***") or diag($@);
my $constructor = RMI::TestClass1->can("new");
ok($constructor, "constructor is now available for the test class");
my $path = $INC{"RMI/TestClass1.pm"};
ok($path, "after proxying the class, it appears in %INC as though it has been 'used'");

eval "use RMI::TestClass1";
my $path2 = $INC{"RMI/TestClass1.pm"};
ok($path2, "attempts to 'use' the proxied class do have no effect");
is(RMI::TestClass1->can("new"),$constructor,"after attempt to 'use' the class, the constructor is the same");

my $remote1 = RMI::TestClass1->new(name => 'remote1');
ok($remote1, "created a remote object using regular/local syntax");
ok($remote1->UNIVERSAL::isa("RMI::ProxyObject"), "real class on remote object is a proxy object");
isa_ok($remote1,"RMI::TestClass1", "isa returns true when used with the proxied class");

is($remote1->m1, $c->peer_pid, "object method returns a value indicating it ran in the other process");
ok($remote1->m1 != $$, "object method returns a value indicating it did not run in this process");

ok($c->close, "closed the client connection");
exit;
