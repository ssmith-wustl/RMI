#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 5;
use IO::Handle;     # thousands of lines just for autoflush :−(

use_ok("RMI");
use_ok("RMI::Client");

my $c = RMI::Client->new("fork/pipes");
my $pid = $c->{server_pid};
my $reader = $c->{reader};
my $writer = $c->{writer};

my @result;

@result = RMI::call($writer, $reader, undef, 'main::f1', 2, 3); 
is($result[0], $pid, "retval indicates the method was called in the child/server process");
is($result[1], 5, "result value $result[1] is as expected for 2 + 3");

@result = RMI::call($writer, $reader, undef, 'main::f1', 6, 7);
is($result[1], 13, "result value $result[1] is as expected for 6 + 7");  

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


