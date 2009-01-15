
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

sub call_eval {
    my ($self,$src) = @_;
    return $self->send_request_and_receive_response(undef, 'RMI::Node::_eval', $src);
}

sub call_use {
    my $self = shift;
    for my $class (@_) {
        $self->send_request_and_receive_response(undef, 'RMI::Node::_eval', "use $class");
    }    
    return scalar(@_);    
}

sub call_use_lib {
    my $self = shift;
    for my $class (@_) {
        $self->send_request_and_receive_response(undef, 'RMI::Node::_eval', "use lib '$class'");
    }    
    return scalar(@_);    
}

sub use_remote {
    my $self = shift;
    for my $class (@_) {
        $self->call_use($class);
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
        #print $src;
        my $r = $self->call_eval($src);
        die $@ if $@;
        #print "got $r\n";
        $src = '*' . $full_var . ' = $r' . ";\n";
        #print $src;
        eval $src;
        die $@ if $@;
    }
    return scalar(@_);
}

=pod

=head1 NAME

RMI::Client - a connection to an RMI::Server

=head1 SYNOPSIS

 $c = RMI::Client->new(reader => $fh1, writer => $fh2);
 $o = $c->call_class_method('IO::File','new','/tmp/myfile');

 $c1 = RMI::Client::Tcp->new(host => 'server1', port => 1234);
 $c1->call_use('Sys::Hostname');
 $host = $c1->call_function('Sys::Hostname::hostname')
 $host eq 'server1'; #!
 
 $c2 = RMI::Client::ForkedPipes->new();
 $pid = $c2->call_eval('$$');
 $pid != $$;
 
 $h1 = $c1->call_eval({ k1 => 111, k2 => 222, k3 => 333});
 @keys = $c2->call_eval('sort keys %{ $_[0] }', $h1);
 is_deeply(\@keys,['k1','k2','k3']);
 
=head1 DESCRIPTION

This is the base class for a standard RMI connection to an RMI::Server.


=head1 METHODS


=head1 EXAMPLES



=head1 BUGS AND CAVEATS

See general bugs in B<RMI> for general system limitations

=head1 SEE ALSO

B<RMI::Server> B<RMI::Client>

B<IO::Socket>, B<Tie::Handle>, B<Tie::Array>, B<Tie:Hash>, B<Tie::Scalar>

=cut


1;

