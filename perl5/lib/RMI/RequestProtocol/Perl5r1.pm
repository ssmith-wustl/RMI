package RMI::RequestProtocol::Perl5r1;
use strict;
use warnings;

sub new {
    my ($class, $node) = @_;
    my $self = bless { node => $node }, $class;
    Scalar::Util::weaken($self->{node});
    return $self;
}

# used by the requestor to capture context

sub _capture_context {
    return (caller(1))[5]    
}

# used by the requestor to use that context after a result is returned

sub _return_result_in_context {
    my ($self, $response_data, $context) = @_;

    if ($context) {
        print "$RMI::DEBUG_MSG_PREFIX N: $$ returning list @$response_data\n" if $RMI::DEBUG;
        return @$response_data;
    }
    else {
        print "$RMI::DEBUG_MSG_PREFIX N: $$ returning scalar $response_data->[0]\n" if $RMI::DEBUG;
        return $response_data->[0];
    }
}

# used by the responder to process the message data, with embedded context

sub _process_request_in_context_and_return_response {
    my ($self, $message_data) = @_;
    my $node = $self->{node};
    
    my $call_type = shift @$message_data;


    # for all Perl calls, the context is the value of wantarray(): 1, 0 or undef.
    # we capture this in one place so we don't have redundant code in every
    # responder method
    my $context = shift @$message_data;
    my $wantarray = $context;
    
    do {    
        no warnings;
        print "$RMI::DEBUG_MSG_PREFIX N: $$ processing request $call_type in wantarray context $wantarray with : @$message_data\n" if $RMI::DEBUG;
    };
    
    # swap call_ for _respond_to_
    my $method = __PACKAGE__ . '::_respond_to_' . substr($call_type,5);
    
    my @result;

    push @RMI::executing_nodes, $node;
    eval {
        if (not defined $wantarray) {
            print "$RMI::DEBUG_MSG_PREFIX N: $$ object call with undef wantarray\n" if $RMI::DEBUG;
            $self->$method(@$message_data);
        }
        elsif ($wantarray) {
            print "$RMI::DEBUG_MSG_PREFIX N: $$ object call with true wantarray\n" if $RMI::DEBUG;
            @result = $self->$method(@$message_data);
        }
        else {
            print "$RMI::DEBUG_MSG_PREFIX N: $$ object call with false wantarray\n" if $RMI::DEBUG;
            my $result = $self->$method(@$message_data);
            @result = ($result);
        }
    };
    pop @RMI::executing_nodes;

    # we MUST undef these in case they are the only references to remote objects which need to be destroyed
    # the DESTROY handler will queue them for deletion, and _send() will include them in the message to the other side
    @$message_data = ();
    
    my ($return_type, $return_data);
    if ($@) {
        print "$RMI::DEBUG_MSG_PREFIX N: $$ executed with EXCEPTION (unserialized): $@\n" if $RMI::DEBUG;
        ($return_type, $return_data) = ('exception',[$@]);
    }
    else {
        print "$RMI::DEBUG_MSG_PREFIX N: $$ executed with result (unserialized): @result\n" if $RMI::DEBUG;
        ($return_type, $return_data) =  ('result',\@result);
    }
     
    return ($return_type, $return_data);
}

sub _respond_to_function {
    my ($self, $pkg, $sub, @params) = @_;
    no strict 'refs';
    my $fname = $pkg . '::' . $sub;
    $fname->(@params);
}

sub _respond_to_class_method {
    my ($self, $class, $method, @params) = @_;
    $class->$method(@params);
}

sub _respond_to_object_method {
    my ($self, $class, $method, $object, @params) = @_;
    $object->$method(@params);
}

sub _respond_to_use {
    my ($self,$class,$dummy_no_method,$module,$has_args,@use_args) = @_;

    no strict 'refs';
    if ($class and not $module) {
        $module = $class;
        $module =~ s/::/\//g;
        $module .= '.pm';
    }
    elsif ($module and not $class) {
        $class = $module;
        $class =~ s/\//::/g;
        $class =~ s/.pm$//; 
    }
    
    my $n = $RMI::Exported::count++;
    my $tmp_package_to_catch_exports = 'RMI::Exported::P' . $n;
    my $src = "
        package $tmp_package_to_catch_exports;
        require $class;
        my \@exports = ();
        if (\$has_args) {
            if (\@use_args) {
                $class->import(\@use_args);
                \@exports = grep { ${tmp_package_to_catch_exports}->can(\$_) } keys \%${tmp_package_to_catch_exports}::;
            }
            else {
                # print qq/no import because of empty list!/;
            }
        }
        else {
            $class->import();
            \@exports = grep { ${tmp_package_to_catch_exports}->can(\$_) } keys \%${tmp_package_to_catch_exports}::;
        }
        return (\$INC{'$module'}, \@exports);
    ";
    my ($path, @exported) = eval($src);
    die $@ if $@;
    return ($class,$module,$path,@exported);
}

sub _respond_to_use_lib {
    my $self = shift;
    my $dummy_no_class = shift;
    my $dummy_no_method = shift;
    my @libs = @_;
    require lib;
    return lib->import(@libs);
}

sub _respond_to_eval {
    my $self = shift;
    my $dummy_no_class = shift;
    my $dummy_no_method = shift;
    
    my $src = shift;
    if (wantarray) {
        my @result = eval $src;
        die $@ if $@;
        return @result;        
    }
    else {
        my $result = eval $src;
        die $@ if $@;
        return $result;
    }
}

sub _respond_to_coderef {
    # This is used when a CODE ref is proxied, since you can't tie CODE refs.
    # It does not have a matching caller in RMI::Client.
    # The other reference types are handled by "tie" to RMI::ProxyReferecnce.

    # NOTE: It's important to shift these two parameters off since goto must 
    # pass the remainder of @_ to the subroutine.
    my $self = shift;
    my $dummy_no_class = shift;
    my $dummy_no_method = shift;
    my $sub_id = shift;
    my $node = $self->{node};
    my $sub = $node->{_sent_objects}{$sub_id};
    Carp::confess("no coderef $sub_id in the list of sent CODE refs, but a proxy thinks it has this value?") unless $sub;
    die "$sub is not a CODE ref.  came from $sub_id\n" unless $sub and ref($sub) eq 'CODE';
    goto $sub;
}

# BASIC API -- implemented by all protocols --

sub bind_local_var_to_remote {
    # this proxies a single variable

    my $self = shift;
    my $node = $self->{node};
    
    my $local_var = shift;
    my $remote_var = (@_ ? shift : $local_var);
    
    my $type = substr($local_var,0,1);
    if (index($local_var,'::')) {
        $local_var = substr($local_var,1);
    }
    else {
        my $caller = caller();
        $local_var = $caller . '::' . substr($local_var,1);
    }

    unless ($type eq substr($remote_var,0,1)) {
        die "type mismatch: local var $local_var has type $type, while remote is $remote_var!";
    }
    if (index($remote_var,'::')) {
        $remote_var = substr($remote_var,1);
    }
    else {
        my $caller = caller();
        $remote_var = $caller . '::' . substr($remote_var,1);
    }
    
    my $src = '\\' . $type . $remote_var . ";\n";
    my $r = $node->call_eval($src);
    die $@ if $@;
    $src = '*' . $local_var . ' = $r' . ";\n";
    eval $src;
    die $@ if $@;
    return 1;
}


sub bind_local_class_to_remote {
    # this proxies an entire class instead of just a single object
    
    my $self = shift;
    my $node = $self->{node};
    
    my ($class,$module,$path,@exported) = $node->call_use(@_);
    my $re_bind = 0;
    if (my $prior = $RMI::proxied_classes{$class}) {
        if ($prior != $node) {
            die "class $class has already been proxied by another RMI client: $prior!";
        }
        else {
            # re-binding a class to the same remote side doesn't hurt,
            # and allowing it allows the effect of export to occur
            # in multiple places on the client side.
        }
    }
    elsif (my $path = $INC{$module}) {
        die "module $module has already been used locally from path: $path";
    }
    no strict 'refs';
    for my $sub (qw/AUTOLOAD DESTROY can isa/) {
        *{$class . '::' . $sub} = \&{ 'RMI::ProxyObject::' . $sub }
    }
    if (@exported) {
        my $caller ||= caller(0);
        if (substr($caller,0,5) eq 'RMI::') { $caller = caller(2) }  # change this num as we move this method
        for my $sub (@exported) {
            my @pair = ('&' . $caller . '::' . $sub => '&' . $class . '::' . $sub);
            print "$RMI::DEBUG_MSG_PREFIX N: $$ bind pair $pair[0] $pair[1]\n" if $RMI::DEBUG;
            $self->bind_local_var_to_remote(@pair);
        }
    }
    $RMI::proxied_classes{$class} = $node;
    $INC{$module} = $node;
    print "$class used remotely via $self ($node).  Module $module found at $path remotely.\n" if $RMI::DEBUG;    
}


# for cases where we really do want to transfer the original data...

sub _create_remote_copy {
    my ($self,$v) = @_;
    my $node = $self->{node};
    my $serialized = 'no strict; no warnings; ' . Data::Dumper->new([$v])->Terse(1)->Indent(0)->Useqq(1)->Dump();
    my $proxy = $node->send_request_and_receive_response('call_eval','','',$serialized);
    return $proxy;
}

sub _create_local_copy {
    my ($self,$v) = @_;
    my $node = $self->{node};
    my $serialized = $node->send_request_and_receive_response('call_eval','','','Data::Dumper::Dumper($_[0])',$v);
    my $local = eval('no strict; no warnings; ' . $serialized);
    die 'Failed to serialize!: ' . $@ if $@;
    return $local;    
}

# interrogate the remote side
# TODO: this should be part of the node API and accessing the remote node should provide an answer

sub _is_proxy {
    my ($self,$obj) = @_;
    my $node = $self->{node};
    $node->send_request_and_receive_response('call_eval', '', '', 'my $id = "$_[0]"; my $r = exists $RMI::executing_nodes[-1]->{_sent_objects}{$id}; return $r', $obj);
}

sub _has_proxy {
    my ($self,$obj) = @_;
    my $node = $self->{node};    
    my $id = "$obj";
    $node->send_request_and_receive_response('call_eval', '', '', 'exists $RMI::executing_nodes[-1]->{_received_objects}{"' . $id . '"}');
}

sub _remote_node {
    my ($self) = @_;
    my $node = $self->{node};    
    $node->send_request_and_receive_response('call_eval', '', '', '$RMI::executing_nodes[-1]');
}

1;

=pod

=head1 NAME

RMI::RequestProtocol::Perl5r1

=head1 VERSION

This document describes RMI::RequestProtocol::Perl5r1 for RMI v0.11.

=head1 DESCRIPTION

The RMI::RequestProtocol::Perl5r1 module handles responding to requests in the
perl5r1 request protocol format.


=head1 SEE ALSO

B<RMI>, B<RMI::Node>

=head1 AUTHORS

Scott Smith <sakoht@cpan.org>

=head1 COPYRIGHT

Copyright (c) 2008 - 2010 Scott Smith <sakoht@cpan.org>  All rights reserved.

=head1 LICENSE

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

The full text of the license can be found in the LICENSE file included with this
module.

=cut
