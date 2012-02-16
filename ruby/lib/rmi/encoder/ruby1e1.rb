require 'rmi'

class RMI::Encoder::Ruby1e1 < RMI::Encoder

@@value = 0
@@object_reference = 1
@@return_proxy = 3

@@remote_id_for_object = {}
@@sent_objects = {}
@@received_objects = {}
@@node_for_object = {}

def _is_primitive(v)
    if v.kind_of?(String)
        return true
    elsif v.kind_of?(Fixnum)
        return true
    else
        return false
    end
end

def encode(message_data, opts) 
    encoded = []
    message_data.each { |o|
        klass = o.class
        if ! _is_primitive(o)
            # sending some sort of reference
            remote_id = @@remote_id_for_object[o.__id__] 
            if remote_id != nil
                # this is a proxy object on THIS side: the real object will be used on the remote side
                $RMI_DEBUG && print("#{$RMI_DEBUG_MSG_PREFIX} N: #{$$} proxy #{o} references remote #{remote_id}\n")
                encoded.push(@@return_proxy, remote_id)
                next
            elsif (opts != nil and (opts['copy'] == true or opts['copy_params'] == true))
                # a reference on this side which should be copied on the other side instead of proxied
                # this never happens by default in the RMI modules, only when specially requested for performance
                # or to get around known bugs in the C<->Perl interaction in some modules (DBI).
                o = _create_remote_copy(o)
                redo
            else 
                # a reference originating on this side: send info so the remote side can create a proxy

                # TODO: use something better than stringification since this can be overridden!!!
                local_id = o.__id__
                
                #if (allowed = self->{allow_modules})
                #    unless (allowed->{ref(o)})
                #        die "objects of type " + ref(o) + " cannot be passed from this RMI node!"
                #    end 
                #end
                
                encoded.push(@@object_reference, local_id)
                @@sent_objects[local_id] = o
            end
        else 
            # sending a non-reference value
            encoded.push(@@value, o)
        end 
    } 

    return encoded
end


# decode from a Perl5::E1 remote node
def decode(encoded)
    
    message_data = []

    while encoded.length > 0 
        type = encoded.shift()
        value = encoded.shift()
        if type == @@value
            # primitive value
            $RMI_DEBUG && print("#{$RMI_DEBUG_MSG_PREFIX} N: #{$$} - primitive #{value}\n")
            message_data.push(value)
        elsif type == @@object_reference
            # exists on the other side: we need a proxy for it
            o = @@received_objects[value]
            if o == nil
                # it is not already proxied on this side
                #if (RMI::proxied_classes{remote_class})
                #    bless o, remote_class
                #}
                #else 
                #    # Put the object into a custom subclass of RMI::ProxyObject
                #    # this allows class-wide customization of how proxying should
                #    # occur.  It also makes Data::Dumper results more readable.
                #    target_class = 'RMI::Proxy::' + remote_class
                #    unless (RMI::classes_with_proxied_objects{remote_class})
                #        no strict 'refs'
                #        {target_class + '::ISA'} = ('RMI::ProxyObject')
                #        
                #        
                #        local SIG{__DIE__} = undef
                #        local SIG{__WARN__} = undef
                #        eval "use target_class"
                #        RMI::classes_with_proxied_objects{remote_class} = 1
                #    }
                #    bless o, target_class    
                #end 
                o = RMI::ProxyObject.new()
                o_id = o.__id__
                @@received_objects[value] = WeakRef.new(o)
                @@node_for_object[o_id] = @node
                @@remote_id_for_object[o_id] = value
            end 
            
            message_data.push(o)
            $RMI_DEBUG && print("#{$RMI_DEBUG_MSG_PREFIX} N: #{$$} - made proxy for #{value}\n")
        elsif type == @@return_proxy
            # exists on this side, and was a proxy on the other side: get the real reference by id
            o = @@sent_objects[value]
            if o == nil
                msg = "#{$RMI_DEBUG_MSG_PREFIX} N: #{$$} reconstituting local object #{value}, but not found in sent objects!\n"
                raise IOError, msg
            end
            message_data.push(o)
            $RMI_DEBUG && print("#{$RMI_DEBUG_MSG_PREFIX} N: #{$$} - resolved local object for #{value}\n")
        else 
            raise ArgumentError, "Unknown type #{type}????"
        end
    end 

    return message_data
end

=begin

=pod

=head1 NAME

RMI::Encoder::ruby1e1

=head1 VERSION

This document describes RMI::Encoder::Perl5e1 for RMI v0.11.

=head1 DESCRIPTION

All encoding protocol modules have an encode() method which takes an array of values and 
return an array which has no references.  The complimentary decode() method 
must be able to take a copy of the encode() results, in another process on the opposite 
side of the node pair, and turn it into something which behaves like the original array.

The RMI::Encoder::Perl5e1 module handles encode/decode for RMI nodes where
the remote node specifies perl5e1 as its encoding.  It uses a simple 4-value system
of categorizing a data value, and the categorized value, when a reference, embeds both
the class/module and the object identity.

This implementation is in Perl, so it is used for Perl processes to talk with each other.
For a process in another language to talk with a Perl process, it could implement a
Perl5e1 encoding module.  Alternatively, that process's language could implement an
encoding module for which there is a Perl implementation.

Currently, each RMI Node knows its encoding protocol, and it is up to the constructor
of the node to ensure that it is using a protocol which matches the protocol on the other
side.  In a future release auto-negotiation of protocols could be implemented, but 
because RMI is meant to be a low-level protocol, behind layers which handle things like
security and asynchronicity, this may be left out of this layer.

=head1 METHODS

=head2 encode

Turns an array of real data values which contain references into an array
of values which contains no references.

=head2 decode

Takes an array made by encode on the other side, and turns it into an array
which functions like the one which was originally encoded.

=head2 ENCODING

An array of message_data of length n to is converted to have a length of n*2.
Each value is preceded by an integer which categorizes the value.

  0    a primitive, non-reference value
       
       The value itself follows, it is not a reference, and it is passed by-copy.
       
  1    an object reference originating on the sender's side
 
       A unique identifier for the object follows instead of the object.
       The remote side should construct a transparent proxy which uses that ID.
       
  2    a non-object (unblessed) reference originating on the sender's side
       
       A unique identifier for the reference follows, instead of the reference.
       The remote side should construct a transparent proxy which uses that ID.
       
  3    passing-back a proxy: a reference which originated on the receiver's side
       
       The following value is the identifier the remote side sent previously.
       The remote side should substitue the original object when deserializing

=head1 SEE ALSO

B<RMI>, B<RMI::Node>

=head1 AUTHORS

Scott Smith <sakoht@cpan.org>

=head1 COPYRIGHT

Copyright (c) 2008 - 2010 Scott Smith <sakoht@cpan.org>  All rights reserved.

=head1 LICENSE

This program is free software you can redistribute it and/or modify it under
the same terms as Perl itself.

The full text of the license can be found in the LICENSE file included with this
module.

=cut

1


=end

end
