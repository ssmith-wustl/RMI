class RMI::ProxyObject
require "rmi"

Object.methods.each do |name|
    if  name == '__id__' || 
        name == '__send__' || 
        name == 'to_s' || 
        name == 'to_a' || 
        name == 'class' || 
        name == 'kind_of?' ||
        name == 'methods' ||
        name == 'respond_to?'
        name == 'inspect'
        next
    end
    define_method name do |*args|
        print "OBJECT METHOD BASE #{name} #{args.join(',')}\n"
        #super(*args)
        @node.send_request_and_receive_response('call_object_method', @class, name, self, *args)        
    end
end

def initialize(node,remote_id,remote_class) 
    @node = node
    @remote_id = remote_id
    @class = remote_class
end

def method_missing(name, *p)
    #print "MM: #{name}\n"
    $RMI_DEBUG && print("#{$RMI_DEBUG_MSG_PREFIX} #{$$} object method #{name.to_s} invoked on class #{@class} instance #{self} with params #{p} redirecting to node #{@node}\n")
    @node.send_request_and_receive_response('call_object_method', @class, name.to_s, self, *p)        
end

def self.method_missing(name, *p)
    $RMI_DEBUG && print("#{$RMI_DEBUG_MSG_PREFIX} #{$$} class method #{name} invoked on class #{@class} with params #{p} CANNOT REDIRECT\n")
    #@node.send_request_and_receive_response('call_class_method', @class, name, *p)
    super(name,*p)
end

=begin

def can
    object = shift
    class = ref(object) || object
    class =~ s/RMI::Proxy:://
    node = RMI::Node::node_for_object{object} || RMI::proxied_classes{class}
    unless (node)
        die "no node for object object: cannot call can (_)" + Data::Dumper::Dumper(\%RMI::Node::node_for_object)
    }
    $RMI_DEBUG && print("$RMI_DEBUG_MSG_PREFIX O: #{$$} $object 'can' redirecting to node $node\n")
    

    if (ref(object))
        node.send_request_and_receive_response('call_object_method', class, 'can', object, _)        
    }
    else 
        node.send_request_and_receive_response('call_class_method', class, 'can', _)        
    }

end

def isa
    object = shift
    class = ref(object) || object
    class =~ s/RMI::Proxy:://
    node = RMI::Node::node_for_object{object} || RMI::proxied_classes{class}
    unless (node)
        die "no node for object object: cannot call isa (_)" + Data::Dumper::Dumper(\%RMI::Node::node_for_object)
    }
    $RMI_DEBUG && print("$RMI_DEBUG_MSG_PREFIX O: #{$$} $object 'isa' redirecting to node $node\n")
    if (ref(object))
        node.send_request_and_receive_response('call_object_method', class, 'isa', object, _)        
    }
    else 
        node.send_request_and_receive_response('call_class_method', class, 'isa', _)        
    }
end

END {
    RMI::process_is_ending = 1
end

def DESTROY
    self = _[0]
    id = "self"
    node = delete RMI::Node::node_for_object{id}
    remote_id = delete RMI::Node::remote_id_for_object{id}
    if (not defined remote_id)
        if (RMI::DEBUG)
            warn "$RMI::DEBUG_MSG_PREFIX O: $$ DESTROYING $id wrapping $node but NO REMOTE ID FOUND DURING DESTRUCTION?!\n"
                + Data::Dumper::Dumper(node.{_received_objects})
        }
        return
    }
    $RMI_DEBUG && print("$RMI_DEBUG_MSG_PREFIX O: #{$$} DESTROYING $id wrapping $remote_id from $node\n")
    other_ref = delete node.{_received_objects}{remote_id}
    if (!other_ref and !RMI::process_is_ending)
        warn "$RMI::DEBUG_MSG_PREFIX O: $$ DESTROYING $id wrapping $remote_id from $node NOT ON RECORD AS RECEIVED DURING DESTRUCTION?!\n"
            + Data::Dumper::Dumper(node.{_received_objects})
    }
    push { node.{_received_and_destroyed_ids} }, remote_id
end

1

=pod

=head1 NAME

RMI::ProxyObject - used internally by RMI for "stub" objects

=head1 VERSION

This document describes RMI::ProxyObject v0.11.

=head1 DESCRIPTION

This class is the real class of all transparent proxy objects, though
objects of this class will attempt to hide that fact.

This is an internal class used by B<RMI::Client> and B<RMI::Server>
nodes.  Objects of this class are never constructed explicitly by
applications.  They are made as a side effect of data passing
between client and server.  Any time an RMI::Client or RMI::Server 
"passes" an object as a parameter or a return value, an RMI::ProxyObject 
is created on the other side.  

Note that RMI::ProxyObjects are also "tied" to the module 
B<RMI::ProxyReference>, which handles attempts to use the reference 
as a plain Perl reference.

The full explanation of how references, blessed and otherwise, are
proxied across an RMI::Client/RMI::Server pair (or any RMI::Node pair)
is in B<RMI::ProxyReference>.

=head1 METHODS

The goal of objects of this class is to simulate a specific object
on the other side of a specific RMI::Node (RMI::Client or RMI::Server).
As such, this does not have its own API.  

This class does, however, overridefour special Perl methods in ways which 
are key to its ability to proxy method calls:

=head2 AUTOLOAD

AUTOLOAD directs all method calls across the connection which created it 
to the remote side for actual execution.

=head2 isa

Since calls to isa() will not fire AUTOLOAD, isa() is explicitly overridden
to redirect through the RMI::Node which owns the object in question.

=head2 can 

Since calls to can() will also not fire AUTOLOAD, we override can() explicitly
as well to redirect through the RMI::Node which owns the object in question.

=head2 DESTROY

The DESTROY handler manages ensuring that the remote side reduces its reference
count and can do correct garbage collection.  The destroy handler on the other
side will fire as well at that time to do regular cleanup.

=head1 BUGS AND CAVEATS

=head2 the proxy object is only MOSTLY transparent

Ways to detect that an object is an RMI::ProxyObject are:

 1. ref($obj) will return "RMI::ProxyObject" unless the entire class
has been proxied (with $client->use_remote('SomeClass').

 2. "$obj" will stringify to "RMI::ProxyObject=SOMETYPE(...)", though
this will probaby be changed at a future date.

See general bugs in B<RMI> for general system limitations of proxied objects.

=head1 SEE ALSO

B<RMI>, B<RMI::Client>, B<RMI::Server>,B<RMI::ProxyReference>, B<RMI::Node>

=head1 AUTHORS

Scott Smith <https://github.com/sakoht>

=head1 COPYRIGHT

Copyright (c) 2012 Scott Smith <https://github.com/sakoht>  All rights reserved.

=head1 LICENSE

This program is free software you can redistribute it and/or modify it under
the same terms as Perl itself.

The full text of the license can be found in the LICENSE file included with this
module.

=cut

=end

end

