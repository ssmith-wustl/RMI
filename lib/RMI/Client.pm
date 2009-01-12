
package RMI::Client;

use strict;
use warnings;
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

sub use_remote {
    my $self = shift;
    for my $class (@_) {
        $self->send_request_and_receive_response(undef, 'RMI::Node::_eval', "use $class");
        $self->_implement_class_locally_to_proxy($class);
    }
    return 1;
}

sub use_lib_remote {
    my $self = shift;
    unshift @INC, $self->virtual_lib;
}


1;

