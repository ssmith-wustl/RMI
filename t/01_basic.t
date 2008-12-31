#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 30;
use IO::Handle;     # thousands of lines just for autoflush :−(

use_ok("RMI");
use_ok("RMI::Client");

my $c = RMI::Client->new("fork/pipes");
my $pid     = $c->{peer_pid};
my $reader  = $c->{reader};
my $writer  = $c->{writer};

# check the count of objects sent and received after each call
my $sent = $c->{sent};
my $received = $c->{received};
sub expect_counts {
    my ($sent_count, $received_count) = @_;
    is(scalar(keys(%$sent)), $sent_count, "count of sent objects is $sent_count, as expected");
    is(scalar(keys(%$received)), $received_count, "count of sent objects is $received_count, as expected");    
}

my @result;
my $result;

diag("basic remote function attempt 1");
@result = $c->call_function('main::f1', 2, 3); 
is($result[0], $pid, "retval indicates the method was called in the child/server process");
is($result[1], 5, "result value $result[1] is as expected for 2 + 3");
expect_counts(0,0);

diag("basic remote function attempt 2");
@result = $c->call_function('main::f1', 6, 7);
is($result[1], 13, "result value $result[1] is as expected for 6 + 7");  
expect_counts(0,0);

diag("remote eval");
my $rpid = RMI::call($writer, $reader, $sent, $received, undef, "eval", '$$');
ok($rpid > $$, "got pid for other process: $rpid, which is > $$");
expect_counts(0,0);

diag("local object call");
my $local1 = RMI::Test::Class1->new(foo => 111);
ok($local1, "made a local object");
@result = $local1->m1();
ok(scalar(@result), "called method locally");
is($result[0], $$, "result value $result[0] matches pid $$");  
expect_counts(0,0);

diag("request that remote server do a method call on a local object, which just comes right back");
@result = RMI::call($writer, $reader, $sent, $received, $local1, 'm1');
ok(scalar(@result), "called method remotely");
is($result[0], $$, "result value $result[0] is matches pid $$");  
expect_counts(1,0);

diag("make a remote object");
my $r = RMI::call($writer, $reader, $sent, $received, 'RMI::Test::Class1', 'new');
ok($r, "got an object");
isa_ok($r,"RMI::ProxyObject") or diag(Data::Dumper::Dumper($r));
expect_counts(1,1);

diag("call methods on the remote object");

$result = $r->m2(8);
is($result, 16, "return values is as expected for remote object with primitive params");

$result = $r->m3($local1);
is($result, $$, "return values are as expected for remote object with local object params");

my ($r2) = RMI::call($writer, $reader, $sent, $received, 'RMI::Test::Class1', 'new');
ok($r2, "made another remote object to use for a more complicated method call");
$result = $r->m3($r2);
ok($result != $$, "return value is as expected for remote object with remote object params");

$result = $r->m4($r2,$local1);
is($result, "$rpid.$$.$$", "result $result has other process id, and this process id ($$) 2x");

close $reader; close $writer;
waitpid($pid,0);
exit;


# these may be called from the client or server
sub f1 {
    my ($v1,$v2) = @_;
    return($$, $v1+$v2);
}

sub f2 {
    my ($v1, $v2, $s, $r) = @_;
}

package RMI::Test::Class1;

sub new {
    my $class = shift;
    return bless { pid => $$, @_ }, $class;
}

sub m1 {
    my $self = shift;
    return $self->{pid};
}

sub m2 {
    my $self = shift;
    my $v = shift;
    return($v*2);
}

sub m3 {
    my $self = shift;
    my $other = shift;
    $other->m1;
}

sub m4 {
    my $self = shift;
    my $other1 = shift;
    my $other2 = shift;
    my $p1 = $other1->m1;
    my $p2 = $other2->m1;
    my $p3 = $other1->m3($other2);
    return "$p1.$p2.$p3";
}


