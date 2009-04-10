
version = '0.06'

import os
import pprint

# for debugging output
pp = pprint.PrettyPrinter(indent=4)

# required for some methods on the remote side to find the RMI node acting upon them
executing_nodes = [] # required for some methods on the remote side to find the RMI node acting upon them

# tracks classes which have been fully proxied into this process by some client
proxied_classes = {} # tracks classes which have been fully proxied into this process by some client

# inside-out tracking of remote object characteristics keeps us from having to possibly taint their API
node_for_object = {}
remote_id_for_object = {}

# turn on debug messages if an environment variable is set
#if os.eviron.has_key('RMI_DEBUG'):
#    DEBUG = os.environ['RMI_DEBUG']
DEBUG = 0

# this is used at the beginning of each debug message
# setting it to a single space for a server makes server/client distinction
# more readable in combined output.
DEBUG_MSG_PREFIX = ''

class Message:
    def __init__(self,ptype,pdata):
        self.message_type = ptype;
        self.message_data = pdata;

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
        if RMI.DEBUG: 
            print("RMI.DEBUG_MSG_PREFIX N: $$ calling via $self on $object: $method with @$params\n")
        
        sendable = [method,0,object];
        for p in params:
            sendable.push, p

        if not self._send(Message('query',sendable)):
            throw("failed to send! $!")

        while True: 
            received = self._receive()
            if received.message_type == 'result': 
                if RMI.DEBUG:
                    print("$RMI::DEBUG_MSG_PREFIX N: $$ returning scalar $message_data->[0]\n")
                return received.message_data
            elif received.message_type == 'close':
                return
            elif received.message_type == 'query':
                self._process_query(received.message_data)
            elif received.message_type == 'exception':
                throw(received.message_data)
            else:
                throw("unexpected message type from RMI message:" % received.message_type)
            
    def receive_request_and_send_response(self):
        received = self._receive()
        
        if received.message_type == 'query':
            response = self._process_query(received.message_data)
            return [received.message_type, received.message_data, response.response_type, response.response_data]
        elif received.message_type == 'close': 
            return;
        else:
            throw("Unexpected message type " % received.message_type % '!  message_data was:' % pp.pprint(received.message_data))
        

    def _send(self, message):
        s = self._serialize(message);
        if (RMI.DEBUG):
            print("$RMI::DEBUG_MSG_PREFIX N: $$ sending: $s\n")
        return(self.writer.write(s,"\n"))

    def _receive(self):
        if (RMI.DEBUG):
            print("$RMI::DEBUG_MSG_PREFIX N: $$ receiving\n")

        serialized_blob = self.reader.getline

        if (not defined(serialized_blob)):
            # a failure to get data returns a message type of 'close', and undefined message_data
            if (RMI.DEBUG):
                print("$RMI::DEBUG_MSG_PREFIX N: $$ connection closed\n")
            self.is_closed = 1
            return(Message('close',undef));

        if (RMI.DEBUG):
            print("$RMI::DEBUG_MSG_PREFIX N: $$ got " % serialized_blob)
            if (not defined(serialized_blob)):
                print("\n")

        message = self._deserialize(serialized_blob);
        return (message);

    def _get_dispatcher_for_param_list_length(self,l):
        # TODO: cache these
        s = 'lambda f,a: f('
        for n in range(0,l):
            s = s + 'a[' + str(n) + ']'
            print('n is ' + str(n) + ' for l ' + str(l))
            print(s)
            if n == l-1:
                s = s + ')'
            else:
                s = s + ','
        
        f = eval(s)
        return(f)
        
    def _process_query(self,message_data):
        method = message_data.shift()
        wantarray = message_data.shift()
        object = message_data.shift()
        params = message_data
        
        if RMI.DEBUG:
            print("$RMI::DEBUG_MSG_PREFIX N: $$ unserialized object $object and params: @params\n")
        
        RMI.executing_nodes.push(self)
        
        return_type
        return_data
        try:
            if defined(object):
                if RMI.DEBUG:
                    print("$RMI::DEBUG_MSG_PREFIX N: $$ object call with false wantarray\n") 
                method_ref = getattr(object,method)
            else:
                if RMI.DEBUG:
                    print("$RMI::DEBUG_MSG_PREFIX N: $$ function call with false wantarray\n")
                method_ref = eval(method)
            dispatcher = self._get_distpatcher_for_param_list_length(params.length)
            return_data = dispatcher(method_ref,params)
            return_type = 'result'
            
        except Object(e):
            return_data = e
            return_type = 'exception'
            
        if (return_type == 'exception'):
            if (RMI.DEBUG):
                print("$RMI::DEBUG_MSG_PREFIX N: $$ executed with EXCEPTION (unserialized): $@\n")
        else:
            if (RMI.DEBUG):
                print("$RMI::DEBUG_MSG_PREFIX N: $$ executed with result (unserialized): @result\n")
        
        RMI.executing_nodes.pop
        
        # we MUST undef these in case they are the only references to remote objects which need to be destroyed
        # the DESTROY handler will queue them for deletion, and _send() will include them in the message to the other side
        object = None;
        params = None;
        
        message = Message(return_type, return_data)
        
        self._send(message)
        return(message)
        
    def _is_primitive(self,v):
        if isinstance(v,str):
            return True
        elif isinstance(v,int):
            return True
        elif isinstance(v,float):
            return True
        else:
            return False
        
    def _object_to_id(self,o):
        return(str(o))
        
    def _id_to_class(self,id):
        # my ($remote_class,$remote_shape) = ($value =~ /^(.*?=|)(.*?)\(/);
        # chop $remote_class;
        return(id.substr(1,id.find(' object at ')-1))
            
    def _serialize(self,message):
        sent_objects = self._sent_objects
        
        serialized = [ message.message_type, self._received_and_destroyed_ids ]
        self._received_and_destroyed_ids = []
        
        for o in message.message_data:
            if self._is_primitive(o):
                serialized.push(0)
                serialized.push(ostr);
            else:
                if isinstance(o,ProxyObject) or RMI.proxied_classes[type(o)]:
                    # sending back a proxy, the remote side will convert back to the original value
                    key = RMI.Node.remote_id_for_object[o];
                    if key == None:
                        throw("no id found for object " + str(o) + '?')
                        
                    if RMI.DEBUG:
                        print("$RMI::DEBUG_MSG_PREFIX N: $$ proxy $o references remote $key:\n")
                    serialized.push(3)
                    serialized.push(key)
                    next
                else:
                    # sending an object local to this side, the remote side will convert to 
                    # TODO: use something better than stringification since this can be overridden!!!
                    id = self._object_to_id(o)
                    
                    if self.allow_packages:
                        if not self.allowed[type(o)]:
                            throw("objects of type " + str(type(o)) + " cannot be passed from this RMI node!")
                    
                    serialized.push(1)
                    serialized.push(id)
                    sent_objects[key] = o;

        if RMI.DEBUG:
            print("$RMI::DEBUG_MSG_PREFIX N: $$ $message_type translated for serialization to @serialized\n")

        message_data = None # essential to get the DESTROY handler to fire for proxies we're not holding on-to
 
        if RMI.DEBUG:
            print("$RMI::DEBUG_MSG_PREFIX N: $$ destroyed proxies: @$received_and_destroyed_ids\n")        
        
        serialized_blob = RMI.pp.pprint(serialized)
        
        if RMI.DEBUG:
            print("$RMI::DEBUG_MSG_PREFIX N: $$ $message_type serialized as $serialized_blob\n")
        
        if instr(serialized_blob,'\n'):
            throw("newline found in message data!")
        
        return serialized_blob
        
    def _deserialize(self,serialized_blob):
        serialized = eval(serialized_blob)
        
        message_type = serialized.shift
        if message_type == None:
            throw("unexpected undef type from incoming message: " + serialized_blob)

        received_and_destroyed_ids  = serialized.shift
            
        if RMI.DEBUG:
            print("$RMI::DEBUG_MSG_PREFIX N: $$ processing (serialized): @$serialized\n")

        sent_objects                = self._sent_objects
        received_objects            = self._received_objects
        
        message_data = []
        while (len(serialized)):
            vtype = serialized.shift
            
            if (vtype == 0):
                # primitive value
                value = serialized.shift
                if RMI.DEBUG:
                    print("$RMI::DEBUG_MSG_PREFIX N: $$ - primitive " + str(value) + "\n")
                message_data.push(value)
                
            elif (vtype == 1 or vtype == 2):
                # an object exists on the other side: make a proxy unless we already have one
                # note that type 2 is for Perl non-object references, which Python doesn't ever generate, but may receive
                remote_id = serialized.shift
                o = received_objects[remote_id]
                if not o:    
                    # no proxy for this id yet...
                    remote_class = self._id_to_class(remote_id)
                    remote_shape = self._id_to_shape(remote_id)
                    
                    if remote_shape == 'ARRAY':
                        o = RMI.ProxyObjectList(self,remote_id)
                    elif remote_shape == 'HASH':
                        o = RMI.ProxyObjectDict(self,remote_id)
                    elif remote_shape == 'CODE':
                        o = lambda params: self.send_request_and_receive_response('call_coderef', None, 'RMI::Node::_exec_coderef', [remote_id, params])
                    else:
                        o = RMI.ProxyObject(self,remote_id)
                    
                    received_objects[value] = weakref.ref(o)
                    local_id = self._object_to_id(o)
                    RMI.node_for_object[local_id] = self;
                    RMI.remote_id_for_object[local_id] = remote_id;
                
                message_data.push(o)
                if RMI.DEBUG:
                    print("$RMI::DEBUG_MSG_PREFIX N: $$ - made proxy for $value\n")
            
            elif (type == 3):
                # exists on this side, and was a proxy on the other side: get the real reference by id
                local_id = serialized.shift
                o = sent_objects[local_id] 
                if not o:
                    print("$RMI::DEBUG_MSG_PREFIX N: $$ reconstituting local object $value, but not found in my sent objects!\n")
                message_data.push(o)
                if RMI.DEBUG:
                    print("$RMI::DEBUG_MSG_PREFIX N: $$ - resolved local object for $value\n")
        
        if RMI.DEBUG:
            print("$RMI::DEBUG_MSG_PREFIX N: $$ remote side destroyed: @$received_and_destroyed_ids\n")

        missing = []
        for id in received_and_destroyed_ids:
            found = sent_objects[id]
            if found:
                del sent_objects[id]
            else:
                missing.push(id)
        if len(missing) > 0:
            print("Some IDS not found in the sent list: done: @done, expected: @$received_and_destroyed_ids\n")
        
        return(Message(message_type,message_data))
        
    def _exec_coderef():
        throw(__LINE__)
        '''
        my $sub_id = shift;
        my $sub = $RMI::executing_nodes[-1]{_sent_objects}{$sub_id};
        die "$sub is not a CODE ref.  came from $sub_id\n" unless $sub and ref($sub) eq 'CODE';
        goto $sub;
        '''
        
    def _remote_has_ref():
        throw(__LINE__)
        '''
        my ($self,$obj) = @_;
        my $id = "$obj";
        my $has_sent = $self->send_request_and_receive_response('call_eval', undef, "RMI::Server::_receive_eval", ['exists $RMI::executing_nodes[-1]->{_received_objects}{"' . $id . '"}']);
        '''
        
    def _remote_has_sent():
        throw(__LINE__)
        '''
        my ($self,$obj) = @_;
        my $id = "$obj";
        my $has_sent = $self->send_request_and_receive_response('call_eval', undef, "RMI::Server::_receive_eval", ['exists $RMI::executing_nodes[-1]->{_sent_objects}{"' . $id . '"}']);
        '''

class Client:
    def __init__(self):
        throw(__LINE__)
    def call_function():
        throw(__LINE__)
    def call_class_method():
        throw(__LINE__)
    def call_object_method():
        throw(__LINE__)
    def call_eval():
        throw(__LINE__)
    def call_use():
        throw(__LINE__)
    def call_use_lib():
        throw(__LINE__)
    def use_remote():
        throw(__LINE__)
    def use_lib_remote():
        throw(__LINE__)
    def virtual_lib():
        throw(__LINE__)
    def bind():
        throw(__LINE__)
    def _bind_local_var_to_remote():
        throw(__LINE__)
    def _bind_local_class_to_remote():
        throw(__LINE__)

class Server:
    def __init__(self):
        throw(__LINE__)
    def run():
        throw(__LINE__)
    def _receive_use():
        throw(__LINE__)
    def _receive_use_lib():
        throw(__LINE__)
    def _receive_eval():
        throw(__LINE__)

class ProxyObject:
    def __init__(self):
        throw(__LINE__)
    def AUTOLOAD():
        throw(__LINE__)
    def can():
        throw(__LINE__)
    def isa():
        throw(__LINE__)
    def DESTROY():
        throw(__LINE__)

class ProxyReference:
    def __init__(self):
        throw(__LINE__)
    def TIE():
        throw(__LINE__)
    def AUTOLOAD():
        throw(__LINE__)
    def DESTROY():
        throw(__LINE__)

