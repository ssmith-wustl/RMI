#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 4;
use IO::Handle;     # thousands of lines just for autoflush :−(

sub xis {
    my ($v1, $v2, $msg) = @_;
    return ($v1 eq $v2);
}

my $parent_reader;
my $child_reader;
my $parent_writer;
my $child_writer;

pipe($parent_reader, $child_writer);                # XXX: failure?
pipe($child_reader,  $parent_writer);               # XXX: failure?
$child_writer->autoflush(1);
$parent_writer->autoflush(1);

my $pid;
my $line;

use_ok("RMI");

if (my $pid = fork()) {
    # parent
    close $parent_reader; close $parent_writer;

    my @result = RMI::call($child_writer, $child_reader, undef, 'main::f1', 2, 3); 
    is($result[0], $pid, "retval indicates the method was called in the child/server process");
    is($result[1], 5, "result value is as expected");

    @result = RMI::call($child_writer, $child_reader, undef, 'main::f1', 6, 7);
    is($result[1], 13, "result value is as expected");  

    close $child_reader; close $child_writer;
    waitpid($pid,0);
} else {
    # child
    die "cannot fork: $!" unless defined $pid;
    close $child_reader; close $child_writer;
   
    RMI::serve($parent_reader, $parent_writer); 
   
    close $parent_reader; close $parent_writer;
    exit;
}

sub f1 {
    my ($v1,$v2) = @_;
    return($$, $v1+$v2);
}



