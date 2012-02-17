require 'rmi'
require 'set'

class RMI::Node

    # public API
    attr_accessor :reader, :writer, :local_language, :remote_language, :request_response_protocol, :encoding_protocol, :serialization_protocol, :allow_modules, :is_closed

    def initialize(params = {})
        @reader = nil
        @writer = nil
        
        @local_language = 'ruby'                # always (since this is the Ruby module)
        @remote_language = 'ruby'               # may vary but this is the default
        
        @request_response_protocol = 'ruby1r1'  # define request types and response logic
        @_request_responder = nil
        
        @encoding_protocol = 'ruby1e1'          # encode the request/response into an array w/o references
        @_encoder = nil
        
        @serialization_protocol = 's1'          # determine how to stream the encoded array
        @_serializer = nil
        
        @_sent_objects = {}
        @_received_objects = {}
        @_received_and_destroyed_ids = []
        @_tied_objects_for_tied_refs = {}
    
        module_list = params.delete(:allow_modules) || []
        @allow_modules = Set.new module_list

        params.each { |name,value|
            if self.respond_to? name 
                if name.to_s == 'local_language'
                    raise ArgumentError, 'cannot change the local language'
                end
                self.instance_variable_set('@' + name.to_s,value)
            else
                raise ArgumentError, 'bad parameter ' + name.to_s
            end
        }
    
        # the request response protocol is the top of the protocol stack for RMI
        # this handler takes requests, acts on them, and sends an appropriate response
        require "rmi/request-responder/" + @request_response_protocol
        request_responder_class = Object.const_get("RMI").const_get("RequestResponder").const_get(@request_response_protocol.capitalize)
        @_request_responder = request_responder_class.new(self)

        # encode/decode is the way we turn a set of values into a message without references
        # it varies by the language on the remote end (and this local end)
        # it is independent of the request/response protocol, though that is also language dependent
        require "rmi/encoder/" + @encoding_protocol
        encoder_class = Object.const_get("RMI").const_get("Encoder").const_get(@encoding_protocol.capitalize)
        @_encoder = encoder_class.new(self,@_sent_objects,@_received_objects)
        
        # serialize/deserialize is the way we transmit the encoded array from the encoder/decoder
        require "rmi/serializer/" + @serialization_protocol
        serializer_class = Object.const_get("RMI").const_get("Serializer").const_get(@serialization_protocol.capitalize)
        @_serializer = serializer_class.new(self)
       
        #print "initializing node #{self}\n"
    end

    def close 
        if @reader != @writer
            @writer.close 
        end
        @reader.close
    end 

    def send_request_and_receive_response(call_type,pkg,sub,*params)
        $RMI_DEBUG && print("#{$RMI_DEBUG_MSG_PREFIX} N: #{$$} calling #{call_type} using ns #{pkg} method #{sub} with params #{params}\n")
        
        #opts = RMI::ProxyObject::DEFAULT_OPTS[pkg][sub]
        opts = nil
        $RMI_DEBUG && print("#{$RMI_DEBUG_MSG_PREFIX} N: #{$$} request #{call_type} on #{pkg} #{sub} has default opts #{opts}\n")    

        # lookup context
        context = @_request_responder._capture_context()
        
        # send, with context
        self._send('request', [call_type, context, pkg, sub, *params], opts) # || raise(IOError, "failed to send!")
        
        1.times do 
            (response_type, response_data) = self._receive()
            $RMI_DEBUG && print("#{$RMI_DEBUG_MSG_PREFIX} N: #{$$} recieved #{response_type} with data #{response_data}\n")    
            if (response_type == 'result') 
                if (opts and opts.copy_results == true) 
                    response_data = @_request_responder._create_local_copy(response_data)
                end
                return @_request_responder._return_result_in_context(response_data, context)
            elsif (response_type == 'close') 
                return
            elsif (response_type == 'request') 
                # a counter-request, possibly calling a method on an object we sent...
                (counter_response_type, counter_response_data) = @_request_responder._process_request_in_context_and_return_response(response_data)
                self._send(counter_response_type, counter_response_data)   
                redo
            elsif (response_type == 'exception') 
                raise Object.const_get(response_data[0]), response_data[1]
            else 
                raise "unexpected message type from RMI message: #{response_type}"
            end
        end 
    end
    
    def receive_request_and_send_response
        (message_type, message_data) = self._receive()
        $RMI_DEBUG && print("#{$RMI_DEBUG_MSG_PREFIX} N: #{$$} message type #{message_type} with data #{message_data}\n") 
        if (message_type == 'request')
            # processing the request may involve calling a method and returning a result,
            # or perhaps returning an exception.
            (response_type, response_data) = self._process_request_in_context_and_return_response(message_data)
            self._send(response_type, response_data)         

            # the return value is mostly incidental, in case the server logic wants to log what just happened...
            return message_type, message_data, response_type, response_data
        elsif (message_type == 'close')
            return nil, nil, nil, nil
        else
            raise IOError, "Unexpected message type #{message_type}!  message_data was: #{message_data}"
        end        
    end


    # private API

    attr_accessor :_sent_objects, :_received_objects, :_received_and_destroyed_ids, :_tied_objects_for_tied_refs

    def _send(message_type, message_data, opts = {})

        encoded_message = @_encoder.encode(message_data, opts)
        $RMI_DEBUG && print("#{$RMI_DEBUG_MSG_PREFIX} N: #{$$} #{message_type} translated for serialization to #{encoded_message}\n") 

        # this will cause the DESTROY handler to fire on remote proxies which have only one reference,
        # and will expand what is in _received_and_destroyed_ids...
        message_data.clear 

        # reset the received_and_destroyed_ids, but take a copy first so we can send it
        received_and_destroyed_ids_copy = [] + @_received_and_destroyed_ids
        @_received_and_destroyed_ids.clear
        $RMI_DEBUG && print("#{$RMI_DEBUG_MSG_PREFIX} N: #{$$} destroyed proxies: #{@received_and_destroyed_ids_copy}\n")
        
        # send the message, and also the list of received_and_destroyed_ids since the last exchange
        s = @_serializer.serialize(
            @serialization_protocol,
            @encoding_protocol,
            @request_response_protocol,
            message_type,
            encoded_message,
            received_and_destroyed_ids_copy
        )
        ($RMI_DEBUG || $RMI_DUMP) && print("#{$RMI_DEBUG_MSG_PREFIX} N: #{$$} sending: #{s}\n")
        return @writer.print(s,"\n")                

    end

    def _receive()
        $RMI_DEBUG && print("#{$RMI_DEBUG_MSG_PREFIX} N: #{$$} receiving\n")

        serialized_blob = @reader.gets
        
        # TODO: figure out why not having this breaks test 11...
        print ""

        if serialized_blob == nil
            $RMI_DEBUG && print("#{$RMI_DEBUG_MSG_PREFIX} N: #{$$} connection closed\n")
            @is_closed = 1
            return 'close', nil
        end
        
        $RMI_DEBUG && print("#{$RMI_DEBUG_MSG_PREFIX} N: #{$$} got blob: #{serialized_blob}")
        if $RMI_DEBUG and serialized_blob != nil
            print "\n"
        end
        
        (sproto,eproto,rproto,message_type, encoded_message_data, received_and_destroyed_ids) = @_serializer.deserialize(serialized_blob)
        $RMI_DEBUG && print("#{$RMI_DEBUG_MSG_PREFIX} N: #{$$} got encoded message: #{encoded_message_data}\n")
        
        message_data = @_encoder.decode(encoded_message_data)
        $RMI_DEBUG && print("#{$RMI_DEBUG_MSG_PREFIX} N: #{$$} got decoded message: #{message_data}\n")

        $RMI_DEBUG && print("#{$RMI_DEBUG_MSG_PREFIX} N: #{$$} remote side destroyed: #{received_and_destroyed_ids}\n")
        done = []
        received_and_destroyed_ids.each { |id|
            if (removed = @_sent_objects.delete(id) != nil) 
                done.push(removed)
            end 
        }
        
        unless done.length == received_and_destroyed_ids.length
            print "Some IDS not found in the sent list: done: @done, expected: @received_and_destroyed_ids\n"
        end 

        return message_type, message_data
    end

    def _process_request_in_context_and_return_response(*args)
        return @_request_responder._process_request_in_context_and_return_response(*args)
    end

=begin


# these methods vary by remote request protocol...


def _create_remote_copy
    return shift.{_request_responder}._create_remote_copy(@_)
end

def _create_local_copy
    #
    return shift.{_request_responder}._create_local_copy(@_)
end

def _is_proxy
    return shift.{_request_responder}._is_proxy(@_)
end

def _has_proxy
    return shift.{_request_responder}._has_proxy(@_)
end

def _remote_node
    return shift.{_request_responder}._remote_node(@_)
end

def bind_local_var_to_remote
    return shift.{_request_responder}.bind_local_var_to_remote(@_)
end

def bind_local_class_to_remote
    return shift.{_request_responder}.bind_local_class_to_remote(@_)
end

=pod

=head1 NAME

RMI::Node - base class for RMI::Client and RMI::Server 

=head1 VERSION

This document describes RMI::Node v0.11.

=head1 SYNOPSIS
    
    # applications should use B<RMI::Client> and B<RMI::Server>
    # this example is for new client/server implementors
    
    pipe(client_reader, server_writer)  
    pipe(server_reader,  client_writer)     
    server_writer.autoflush(1)
    client_writer.autoflush(1)
    
    $c = RMI::Node->new(
        reader => $client_reader,
        writer => $client_writer,
    )
    
    $s = RMI::Node->new(
        writer => $server_reader,
        reader => $server_writer,
    )
    
def main::add return $_[0] + $_[1] }
    
    if(fork())
        # service one request and exit
        require IO::File
        s.receive_request_and_send_response()
        exit
    }
    
    # send one request and get the result
    sum = c.send_request_and_receive_response('call_function', 'main', 'add', 5, 6)
    
    # we might have also done..
    robj = c.send_request_and_receive_response('call_class_method', 'IO::File', 'new', '/my/file')
    
    # this only works on objects which are remote proxies:
    txt = c.send_request_and_receive_response('call_object_method', robj, 'getline')
    
=head1 DESCRIPTION

This is the base class for RMI::Client and RMI::Server.  RMI::Client and RMI::Server
both implement a wrapper around the RMI::Node interface, with convenience methods
around initiating the sending or receiving of messages.

An RMI::Node object embeds the core methods for bi-directional communication.
Because the server often has to make counter requests of the client, the pair
will often switch functional roles several times in the process of servicing a
particular call. This class is not technically abstract, as it is fully functional in
either the client or server role without subclassing.  Most direct coding against
this API, however, should be done by implementors of new types of clients/servers.

See B<RMI::Client> and B<RMI::Server> for the API against which application code
should be written.  See B<RMI> for an overview of how clients and servers interact.
The documentation in this module will describe the general piping system between
clients and servers.

An RMI::Node requires that the reader/writer handles be explicitly specified at
construction time.  It also requires and that the code which uses it is be wise
about calling methods to send and recieve data which do not cause it to block
indefinitely. :)

=head1 METHODS

=head2 new()
  
 n = RMI::Node.new(reader => fh1, writer => fh2)

The constructor for RMI::Node objects requires that a reader and writer handle be provided.  They
can be the same handle if the handle is bi-directional (as with TCP sockets, see L<RMI::Client::Tcp>).

=head2 close()

 n.close()

Closes handles, and does any additional required bookeeping.
 
=head2 send_request_and_recieve_response()

 @result = n.send_request_and_recieve_response(call_type,@data)

 @result = n.send_request_and_recieve_response(opts_hashref, call_type, @data)

 This is the method behind all of the call_* methods on RMI::Client objects.
 It is also the method behind the proxied objects themselves (in AUTOLOAD).

 The optional initial hashref allows special serialization control.  It is currently
 only used to force serializing instead of proxying in some cases where this is
 helpful and safe.

 The call_type maps to the client request, and is one of:
    call_function
    call_class_method
    call_object_method
    call_eval
    call_use
    call_use_lib

The interpretation of the @data parameters is dependent on the particular call_type, and
is handled entirely on the remote side.  

=head2 receive_request_and_send_response()

This method waits for a single request to be received from its reader handle, services
the request, and sends the results through the writer handle.
 
It is possible that, while servicing the request, it will make counter requests, and those
counter requests, may yield counter-counter-requests which call this method recursively.

=head2 virtual_lib()

This method returns an anonymous subroutine which can be used in a "use lib $mysub"
call, to cause subsequent "use" statements to go through this node to its partner.
 
 e.x.:
    use lib RMI::Client::Tcp.new(host=>'myserver',port=>1234).virtual_lib
 
If a client is constructed for other purposes in the application, the above
can also be accomplished with: $client->use_lib_remote().  (See L<RMI::Client>)

=head1 INTERNALS: MESSAGE TYPES

The RMI internals are built around sending a "message", which has a type, and an
array of data. The interpretation of the message data array is based on the message
type.

The following message types are passed within the current implementation:

=head2 request

A request that logic execute on the remote side on behalf of the sender.
This includes object method calls, class method calls, function calls,
remote calls to eval(), and requests that the remote side load modules,
add library paths, etc.
  
This is the type for standard remote method invocatons.
  
The message data contains, in order:

 - wantarray    1, '', or undef, depending on the requestor's calling context.
                This is passed to the remote side, and also used on the
                local side to control how results are returned.

 - object/class A class name, or an object which is a proxy for something on the remote side.
                This value is not present for plain function calls, or evals.

 - method_name  This is the name of the method to call.
                This is a fully-qualified function name for plain function calls.

 - param1       The first parameter to the function/method call.
                Note that parameters are "passed" to eval as well by exposing @_.

 - ...          The next parameter to the function/method call, etc.


=head2 result

The return value from a succesful "request" which does not result in an
exception being thrown on the remote side.
  
The message data contains the return value or values of that request.
  
=head2 exception

The response to a request which resulted in an exception on the remote side.
  
The message data contains the value thrown via die() on the remote side.
  
=head2 close

Indicatees that the remote side has closed the connection.  This is actually
constructed on the receiver end when it fails to read from the input stream.
  
The message data is undefined in this case.

=head1 INTERNALS: WIRE PROTOCOL

The _send() and _receive() methods are symmetrical.  These two methods are used
by the public API to encapsulate message transmission and reception.  The _send()
method takes a message_type and a message_data arrayref, and transmits them to
the other side of the RMI connection. The _receive() method returns a message
type and message data array.

Internal to _send() and _receive() the message type and data are passed through
_serialize and _deserialize and then transmitted along the writer and reader handles.

The _serialize method turns a message_type and message_data into a string value
suitable for transmission.  Conversely, the _deserialize method turns a string
value in the same format into a message_type and message_data array.

The serialization process has two stages:

=head2 replacing references with identifiers used for remoting

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

  4    a serialized object

       This is the result of serializing the reference.  This happens only
       when explicitly requested.  (DBI has some issues with proxies, for instance
       and has customizations in RMI::Proxy::DBI::db to force serialization of
       some connection attributes.)

       See B<RMI::ProxyObject> for more details on forcing serialization.

       Note that, because the current wire protocol is to use newline as a record 
       separator, we use double-quoted strings to ensure all newlines are escaped.

Note that all references are turned into primitives by the above process.

=head2 stringification

The "wire protocol" for sending and receiving messages is to pass an array via Data::Dumper
in such a way that it does not contain newlines.  The receiving side uses eval to reconstruct
the original message.  This is terribly inefficient because the structure does not contain
objects of arbitrary depth, and is parsable without tremendous complexity.

Details on how proxy objects and references function, and pose as the real item
in question, are in B<RMI>, and B<RMI::ProxyObject> and B<RMI::ProxyReference>

=head1 BUGS AND CAVEATS

See general bugs in B<RMI> for general system limitations

=head2 the serialization mechanism needs to be made more robust and efficient

It's really just enough to "work".

The current implementation uses Data::Dumper with options which should remove
newlines.  Since we do not flatten arbitrary data structures, a simpler parser
would be more efficient.

The message type is currently a text string.  This could be made smaller.

The data type before each paramter or return value is an integer, which could
also be abbreviated futher, or we could go the other way and be more clear. :)

This should switch to sysread and pass the message length instead of relying on
buffers, since the non-blocking IO might not have issues.

=head1 SEE ALSO

B<RMI>, B<RMI::Server>, B<RMI::Client>, B<RMI::ProxyObject>, B<RMI::ProxyReference>

B<IO::Socket>, B<Tie::Handle>, B<Tie::Array>, B<Tie:Hash>, B<Tie::Scalar>

=head1 AUTHORS

Scott Smith <sakoht@cpan.org>

=head1 COPYRIGHT

Copyright (c) 2008 - 2009 Scott Smith <sakoht@cpan.org>  All rights reserved.

=head1 LICENSE

This program is free software you can redistribute it and/or modify it under
the same terms as Perl itself.

The full text of the license can be found in the LICENSE file included with this
module.

=cut

1

=end

end

