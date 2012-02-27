require 'pp'
require 'stringio'

class RMI::Serializer::S1 < RMI::Serializer

@@PROTOCOL_VERSION = 1
@@PROTOCOL_SYM = @@PROTOCOL_VERSION.chr # ASCII value of the protocol version 

def serialize(sproto, eproto, rproto, message_type, encoded_message_data, received_and_destroyed_ids)
    a = [ 
            sproto, 
            eproto, 
            rproto,
            message_type,
            received_and_destroyed_ids.length
        ]  + 
        received_and_destroyed_ids +
        encoded_message_data

    # TODO: this is turning the array "a" into a string eval-able in Ruby, JSON, Ruby and Python
    # a built-in dumper may be faster, but the structure is so simple it may not be.  Test it.
    serialized_blob = '' 
    a.each do |v|
        if serialized_blob == ''
            serialized_blob = @@PROTOCOL_SYM + '['
        else
            serialized_blob += ', '
        end
        s = StringIO.new
        PP.singleline_pp(v,s)
        s.rewind
        s2 = s.read
        #print "serialized #{v} as #{s2}\n"
        serialized_blob += s2 
        #if v.kind_of?(String)
        #    serialized_blob += "'" + v + "'"
        #else
        #    serialized_blob += v.to_s
        #end
    end
    serialized_blob += ']'

    $RMI_DEBUG && print("#{$RMI_DEBUG_MSG_PREFIX} N: #{$$} #{message_type} serialized as #{serialized_blob}\n") 
    
    return serialized_blob
end

def deserialize(serialized_blob) 

    # the first byte of the message is the ascii value for the protocol version
    message_protocol_sym = serialized_blob[0..0]
    serialized_blob = serialized_blob[1..-1]
    
    unless message_protocol_sym == @@PROTOCOL_SYM
        message_protocol_version = message_protocol_sym[0]
        raise IOError, "Got message with protocol #{message_protocol_version} (symbol #{message_protocol_sym}), expected #{@@PROTOCOL_VERSION} (symbol #{@@PROTOCOL_SYM}) !!"
    end

    $RMI_DEBUG && print("#{$RMI_DEBUG_MSG_PREFIX} N: #{$$} serialized blob is #{serialized_blob}\n") 
    
    encoded_message_data = eval serialized_blob

    $RMI_DEBUG && print("#{$RMI_DEBUG_MSG_PREFIX} N: #{$$} encoded data #{encoded_message_data}\n") 
    
    sproto = encoded_message_data.shift
    eproto = encoded_message_data.shift
    rproto = encoded_message_data.shift
   
    message_type = encoded_message_data.shift
    if message_type == nil
        raise IOError, "unexpected undef type from incoming message:" . Data::Dumper::Dumper(encoded_message_data)
    end

    received_and_destroyed_ids_count = encoded_message_data.shift.to_i
    received_and_destroyed_ids = []
    received_and_destroyed_ids_count.times do 
        id = encoded_message_data.shift
        received_and_destroyed_ids.push(id)
    end

    $RMI_DEBUG && print("#{$RMI_DEBUG_MSG_PREFIX} N: #{$$} encoded data after shifting #{encoded_message_data}\n") 
    
    return sproto, eproto, rproto, message_type, encoded_message_data, received_and_destroyed_ids
end

=begin

=pod

=head1 NAME

RMI::Serializer::S1 - a human-readable, eval-able, depthless serialization protocol

=head1 SYNOPSIS

c = RMI::Client::ForkedPipes.new(serialization_protocol => 'v1')

=head1 DESCRIPTION

All serialization protocol modules take an array of simple text strings and
turn them into a blob which can be transmitted to another process and reconstructed.
It is the lowest-level part of the protocol stack in RMI.  The layer above,
the encoding, turns complex objects into strings (identity values, not data) and back.

The serialization protocol version of an RMI blob is identified by the first byte
of the serialized message.  For version 1 is the exception, it is the ascii value for '[',
which happens to be the first character of an eval-able array in several languages.

This is the default serialization protocol for RMI in Ruby.

By using double-quoted strings, newlines are removed from any message, leading 
to a simple blob format of readable characters with one message per line, and easy 
debugging.  The message is itself eval-able in Ruby, JavaScript, Ruby, Python.

=cut

=end

end
