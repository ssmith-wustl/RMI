#!/usr/bin/env perl

package RMI::Client::Tcp;

use strict;
use warnings;
use base 'RMI::Client';

package UR::DataSource::RemoteCache;

use strict;
use warnings;

# FIXME  This is a bare-bones datasource and only supports read-only connections for now
# There's very minimal error checking.  Some duplication of code between here and
# UR::Service::DataSourceProxy.  The messaging protocol, connection details, etc
# probably need to be refactored into a more general RPC mechanism some time later
#
# In short, It's just here to remind people that it exists and needs to be
# cleaned up later.

require UR;

UR::Object::Type->define(
    class_name => 'UR::DataSource::RemoteCache',
    is => ['UR::DataSource'],
    english_name => 'ur datasource remotecache',
#    is_abstract => 1,
    properties => [
        host => {type => 'String', is_transient => 1},
        port => {type => 'String', is_transient => 1, default_value => 10293},
        socket => {type => 'IO::Socket', is_transient => 1},
    ],
    id_by => ['host','port'],
    doc => "A datasource representing a connection to another process",
);

# FIXME needs real pod docs.  In the mean time, here's how you'd create a program that just
# tells a class to get its data from some other server:
# use GSC;
# my $remote_ds = UR::DataSource::RemoteCache->create(host => 'localhost',port => 10293);
# my $class_object = UR::Object::Type->get(class_name => 'GSC::Clone');
# $class_object->data_source($remote_ds);
# @clones = GSC::Clone->get(10001);


use IO::Socket;

sub create {
    my $class = shift;
    my %params = @_;

    my $obj = $class->SUPER::create(@_);

    return unless $obj;

    unless ($obj->_connect_socket()) {
        $class->error_message(sprintf("Failed to connect to remote host %s:%s",
                                      $params{'host'}, $params{'port'}));
        return;
    }

    return $obj;
}

    

sub _connect_socket {
    my $self = shift;
    
    my $socket = IO::Socket::INET->new(PeerHost => $self->host,
                                       PeerPort => $self->port,
                                       ReuseAddr => 1,
                                       #ReusePort => 1,
                                     );
    unless ($socket) {
        $self->error_message("Couldn't connect to remote host: $!");
        return;
    }

    $self->socket($socket);

    $self->_init_created_socket();

    return 1;
}
                                       

sub _init_created_socket {
    # override in sub-classes
    1;
}


use FreezeThaw;
sub _remote_get_with_rule {
    my $self = shift;

$DB::single=1;
    my $string = FreezeThaw::freeze(\@_);
    my $socket = $self->socket;

    # First word is message length, second is command - 1 is "get"
    $socket->print(pack("LL", length($string),1),$string);

    my $cmd;
    ($string,$cmd) = $self->_read_message($socket);

    unless ($cmd == 129)  {
        $self->error_message("Got back unexpected command code.  Expected 129 got $cmd\n");
        return;
    }
      
    return unless ($string);  # An empty response
    
    my($result) = FreezeThaw::thaw($string);

    return @$result;
}
    
    
# This should be refactored into a messaging module later
sub _read_message {
    my $self = shift;
    my $socket = shift;

    my $buffer = "";
    my $read = $socket->sysread($buffer,8);
    if ($read == 0) {
        # The handle must be closed, or someone set it to non-blocking
        # and there's nothing to read
        return (undef, -1);
    }

    unless ($read == 8) {
        die "short read getting message length";
    }

    my($length,$cmd) = unpack("LL",$buffer);
    my $string = "";
    $read = $socket->sysread($string,$length);

    return($string,$cmd);
}
    


sub create_iterator_closure_for_rule {
    my ($self, $rule) = @_;

    $DB::single = 1;

    # FIXME make this more efficient so that we dispatch the request, and the
    # iterator can fetch one item back at a time
    my @results = $self->_remote_get_with_rule($rule);

    my $iterator = sub {
        my $items_to_return = $_[0] || 1;
     
        return unless @results;
        my @return = splice(@results,0, $items_to_return);

        return @return;
    };

    return $iterator;
}

sub _record_that_loading_has_occurred {    
    my ($self, $param_load_hash) = @_;
    no strict 'refs';
    foreach my $class (keys %$param_load_hash) {
        my $param_data = $param_load_hash->{$class};
        foreach my $param_string (keys %$param_data) {
            $UR::Object::all_params_loaded->{$class}{$param_string} ||=
                $param_data->{$param_string};
        }
    }
}

sub _first_class_in_inheritance_with_a_table {
    # This is called once per subclass and cached in the subclass from then on.
    my $self = shift;
    my $class = shift;
    $class = ref($class) if ref($class);


    unless ($class) {
        $DB::single = 1;
        Carp::confess("No class?");
    }
    my $class_object = $class->get_class_object;
    my $found = "";
    for ($class_object, $class_object->get_inherited_class_objects)
    {                
        if ($_->table_name)
        {
            $found = $_->class_name;
            last;
        }
    }
    #eval qq/
    #    package $class;
    #    sub _first_class_in_inheritance_with_a_table { 
    #        return '$found' if \$_[0] eq '$class';
    #        shift->SUPER::_first_class_in_inheritance_with_a_table(\@_);
    #    }
    #/;
    die "Error setting data in subclass: $@" if $@;
    return $found;
}

sub _class_is_safe_to_rebless_from_parent_class {
    my ($self, $class, $was_loaded_as_this_parent_class) = @_;
    my $fcwt = $self->_first_class_in_inheritance_with_a_table($class);
    die "No parent class with a table found for $class?!" unless $fcwt;
    return ($was_loaded_as_this_parent_class->isa($fcwt));
}


1;

