#!/usr/bin/env perl

package RMI::Client::NamedPipes;

use strict;
use warnings;
use base 'RMI::Client';
use IO::File;     

sub new {
    my ($class,$reader_path,$writer_path) = (@_); 
    my $reader = IO::File->new($reader_path);
    $reader or die "Failed to open reader $reader_path: $!";
    my $writer = IO::File->new('>' . $writer_path);   
    $writer or die "Failed to open writer $writer_path: $!";
    $writer->autoflush(1);

    my $self = $class->SUPER::new(
        peer_pid => -1,
        writer => $writer,
        reader => $reader,
    );

    return $self;    
}

1;

