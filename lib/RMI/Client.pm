#!/usr/bin/env perl

package RMI::Client;

use strict;
use warnings;
use base 'RMI::Node';

sub new {
    my $class = shift;
    my $server = shift;
    if ($server) {
        return $class->_new_from_url($server);    
    }
    else {
        return $class->_new_forked_pipes;        
    }
}

sub call_function {
    my ($self,$fname,@params) = @_;
    return $self->_send(undef, $fname, @params);
}

sub call_class_method {
    my ($self,$class,$method,@params) = @_;
    return $self->_send($class, $method, @params);
}

sub call_object_method {
    my ($self,$object,$method,@params) = @_;
    return $self->_send($object, $method, @params);
}

sub remote_eval {
    my ($self,$src) = @_;
    return $self->_send(undef, 'RMI::Node::_eval', $src);
}

use IO::Handle;     # thousands of lines just for autoflush :(
sub _new_forked_pipes {
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

sub _new_from_url {
    my $class = shift;
    my $url = shift;
    die "new_from_url() not implemented!";
}

1;

