#!/usr/bin/env ruby

use strict;
use warnings;
use Test::More tests => 6;
use FindBin;
use lib $FindBin::Bin;
use Data::Dumper;
use RMI::Client::ForkedPipes;

package Test1;

sub append_to_array {
    my $a = shift;
    push @$a, @_;
    return $a;
}

package Test2;

sub append_to_array {
    my $a = shift;
    push @$a, @_;
    return $a;
}

package main;

$RMI::ProxyObject::DEFAULT_OPTS{"Test2"}{"append_to_array"} = { copy_results => 1 };

my $c = RMI::Client::ForkedPipes->new();
ok($c, "created a test client/server pair");

##

my $a = $c->call_eval("[101..110]");
ok($c->_is_proxy($a), "made a remote arrayref");

my $a1 = $c->call_function('Test1::append_to_array',$a,201..205);
ok($c->_is_proxy($a1), "got a remote proxy back");
is($a1, $a, "got the same array back when NOT copying results");

my $a2 = $c->call_function('Test2::append_to_array',$a,201..205);
ok($a2 != $a, "got the a different array back when copying results");
ok(!$c->_is_proxy($a2), "it is a local object");

