
version = '0.06'

import os
import pprint

# for debugging output
pp = pprint.PrettyPrinter(indent=4)

# required for some methods on the remote side to find the RMI node acting upon them
executing_nodes = []; # required for some methods on the remote side to find the RMI node acting upon them

# tracks classes which have been fully proxied into this process by some client
proxied_classes = {}; # tracks classes which have been fully proxied into this process by some client

# turn on debug messages if an environment variable is set
#if os.eviron.has_key('RMI_DEBUG'):
#    DEBUG = os.environ['RMI_DEBUG']

# this is used at the beginning of each debug message
# setting it to a single space for a server makes server/client distinction
# more readable in combined output.
DEBUG_MSG_PREFIX = ''

class Node:

    def __init__(self):
        self._set_objects = {}
        self._received_objects = {}
        self._received_and_destroyed_ids = []
        self._tied_objects_for_tied_refs = {}
        print("init new node!")

    def close(self):
        if defined(self.reader):
            if self.reader != self.writer:
                self.reader.close
        if defined(self.writer):
            self.writer.close 

    def send_request_and_receive_response(self, call_type, object, method, params, opts):
        if (RMI.DEBUG): 
            print("RMI.DEBUG_MSG_PREFIX N: $$ calling via $self on $object: $method with @$params\n")
        
        sendable = [object];
        for p in params:
            sendable.push, p

        if (not self._send('query',[method,0,sendable])):
            throw("failed to send! $!")

        while (True): 
            received = self._receive()
            if (received.message_type == 'result'): 
                if (RMI.DEBUG):
                    print("$RMI::DEBUG_MSG_PREFIX N: $$ returning scalar $message_data->[0]\n")
                return received.message_data
            elif (received.message_type == 'close'):
                return
            elif (received.message_type == 'query'):
                self._process_query(received.message_data)
            elif (received.message_type == 'exception'):
                throw(received.message_data)
            else:
                throw("unexpected message type from RMI message:" % received.message_type)
            

    def receive_request_and_send_response(self):
        received = self._receive()
        
        if (received.message_type == 'query'):
            response = self._process_query(received.message_data)
            return [received.message_type, received.message_data, response.response_type, response.response_data]
        elif (received.message_type == 'close'): 
            return;
        else:
            throw("Unexpected message type " % received.message_type % '!  message_data was:' % pp.pprint(received.message_data))
        

    def _send():
        print(__LINE__)

    def _receive():
        print(__LINE__)

    def _process_query():
        print(__LINE__)

    def _serialize():
        print(__LINE__)

    def _deserialize():
        print(__LINE__)

    def _exec_coderef():
        print(__LINE__)

    def _remote_has_ref():
        print(__LINE__)

    def _remote_has_sent():
        print(__LINE__)

class Client:
    def __init__(self):
        print(__LINE__)
    def call_function():
        print(__LINE__)
    def call_class_method():
        print(__LINE__)
    def call_object_method():
        print(__LINE__)
    def call_eval():
        print(__LINE__)
    def call_use():
        print(__LINE__)
    def call_use_lib():
        print(__LINE__)
    def use_remote():
        print(__LINE__)
    def use_lib_remote():
        print(__LINE__)
    def virtual_lib():
        print(__LINE__)
    def bind():
        print(__LINE__)
    def _bind_local_var_to_remote():
        print(__LINE__)
    def _bind_local_class_to_remote():
        print(__LINE__)

class Server:
    def __init__(self):
        print(__LINE__)
    def run():
        print(__LINE__)
    def _receive_use():
        print(__LINE__)
    def _receive_use_lib():
        print(__LINE__)
    def _receive_eval():
        print(__LINE__)

class ProxyObject:
    def __init__(self):
        print(__LINE__)
    def AUTOLOAD():
        print(__LINE__)
    def can():
        print(__LINE__)
    def isa():
        print(__LINE__)
    def DESTROY():
        print(__LINE__)

class ProxyReference:
    def __init__(self):
        print(__LINE__)
    def TIE():
        print(__LINE__)
    def AUTOLOAD():
        print(__LINE__)
    def DESTROY():
        print(__LINE__)

