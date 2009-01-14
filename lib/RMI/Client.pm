
package RMI::Client;

use strict;
use warnings;
use version;
our $VERSION = qv('0.1');

use base 'RMI::Node';

*call_sub = \&call_function;

sub call_function {
    my ($self,$fname,@params) = @_;
    return $self->send_request_and_receive_response(undef, $fname, @params);
}

sub call_class_method {
    my ($self,$class,$method,@params) = @_;
    $self->send_request_and_receive_response(undef, 'RMI::Node::_eval', "use $class");
    return $self->send_request_and_receive_response($class, $method, @params);
}

sub call_object_method {
    my ($self,$object,$method,@params) = @_;
    return $self->send_request_and_receive_response($object, $method, @params);
}

sub remote_eval {
    my ($self,$src) = @_;
    return $self->send_request_and_receive_response(undef, 'RMI::Node::_eval', $src);
}

sub remote_use {
    my $self = shift;
    for my $class (@_) {
        $self->send_request_and_receive_response(undef, 'RMI::Node::_eval', "use $class");
    }    
    return scalar(@_);    
}

sub use_remote {
    my $self = shift;
    for my $class (@_) {
        $self->remote_use($class);
        $self->_implement_class_locally_to_proxy($class);
    }
    return scalar(@_);
}

sub use_lib_remote {
    my $self = shift;
    unshift @INC, $self->virtual_lib;
}

sub bind_variables {
    my $self = shift;
    my $caller = caller();
    my $full_var;
    for my $var (@_) {
        my $type = substr($var,0,1);
        if (index($var,'::')) {
            $full_var = substr($var,1);
        }
        else {
            $full_var = $caller . '::' . substr($var,1);
        }
        
        my $src = '\\' . $type . $full_var . ";\n";
        print $src;
        my $r = $self->remote_eval($src);
        die $@ if $@;
        print "got $r\n";
        $src = '*' . $full_var . ' = $r' . ";\n";
        print $src;
        eval $src;
        die $@ if $@;
    }    
}



1;

