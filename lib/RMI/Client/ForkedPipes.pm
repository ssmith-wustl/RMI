#!/usr/bin/env perl

package RMI::Client::ForkedPipes;

use strict;
use warnings;
use base 'RMI::Client';
use IO::Handle;     # thousands of lines just for autoflush :(

my @p = qw/peer_pid/;
for my $p (@p) {
    my $pname = $p;
    no strict 'refs';
    *$p = sub { $_[0]->{$pname} };
}


sub new {
    my $class = $_[0];
    
    my $parent_reader;
    my $parent_writer;
    my $child_reader;
    my $child_writer;
    pipe($parent_reader, $child_writer);  
    pipe($child_reader,  $parent_writer); 
    $child_writer->autoflush(1);
    $parent_writer->autoflush(1);

    # child process acts as a server for this test and then exits
    my $parent_pid = $$;
    my $child_pid = fork();
    die "cannot fork: $!" unless defined $child_pid;
    unless ($child_pid) {
        $child_pid = $$;
        close $child_reader; close $child_writer;
        $RMI::DEBUG_INDENT = '  ';
        my $server = RMI::Server->new(
            peer_pid => $parent_pid,
            writer => $parent_writer,
            reader => $parent_reader,
        );
        $server->start; 
        close $parent_reader; close $parent_writer;
        exit;
    }

    # parent/original process is the client which does tests
    close $parent_reader; close $parent_writer;

    my $self = $class->SUPER::new(
        peer_pid => $child_pid,
        writer => $child_writer,
        reader => $child_reader,
    );

    return $self;    
}

1;

