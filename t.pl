#!/usr/bin/env perl
use strict;
use warnings;

use Test::More tests => 4;
use IO::Handle;     # thousands of lines just for autoflush :−(

sub xis {
    my ($v1, $v2, $msg) = @_;
    return ($v1 eq $v2);
}

my $PARENT_RDR;
my $CHILD_RDR;
my $PARENT_WTR;
my $CHILD_WTR;

pipe($PARENT_RDR, $CHILD_WTR);                # XXX: failure?
pipe($CHILD_RDR,  $PARENT_WTR);               # XXX: failure?
$CHILD_WTR->autoflush(1);
$PARENT_WTR->autoflush(1);

my $pid;
my $line;

use_ok("RMI");
$RMI::DEBUG=1;

if (my $pid = fork()) {
    # parent
   close $PARENT_RDR; close $PARENT_WTR;
   #print $CHILD_WTR "Parent Pid $$ is sending this\n";
   #chomp($line = <$CHILD_RDR>);
   #print "Parent Pid $$ just read this: ‘$line’\n";

    my @result = RMI::call($CHILD_WTR, $CHILD_RDR, undef, 'main::f1', 2, 3); 
    is($result[0], $pid, "retval indicates the method was called in the child/server process");
    is($result[1], 5, "result value is as expected");

    @result = RMI::call($CHILD_WTR, $CHILD_RDR, undef, 'main::f1', 6, 7);
    is($result[1], 13, "result value is as expected");  

   close $CHILD_RDR; close $CHILD_WTR;
   waitpid($pid,0);

} else {
    # child
   die "cannot fork: $!" unless defined $pid;
   close $CHILD_RDR; close $CHILD_WTR;
   #chomp($line = <$PARENT_RDR>);
   #print "Child Pid $$ just read this: ‘$line’\n";
   #print $PARENT_WTR "Child Pid $$ is sending this\n";
   
    RMI::serve($PARENT_RDR, $PARENT_WTR); 
   
   close $PARENT_RDR; close $PARENT_WTR;
   exit;
}

sub f1 {
    my ($v1,$v2) = @_;
    return($$, $v1+$v2);
}



