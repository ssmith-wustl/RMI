
version = '0.06'

import os
import weakref
import pprint
import RMI

# for debugging output
pp = pprint.PrettyPrinter(indent=0,width=10000000)

# required for some methods on the remote side to find the RMI node acting upon them
executing_nodes = [] # required for some methods on the remote side to find the RMI node acting upon them

# tracks classes which have been fully proxied into this process by some client
proxied_classes = {} # tracks classes which have been fully proxied into this process by some client

# inside-out tracking of remote object characteristics keeps us from having to possibly taint their API
node_for_object = {}
remote_id_for_object = {}

# turn on debug messages if an environment variable is set
try:
    DEBUG_FLAG = os.environ['RMI_DEBUG']
except:
    DEBUG_FLAG = 0 

# this is used at the beginning of each debug message
# setting it to a single space for a server makes server/client distinction
# more readable in combined output.
DEBUG_MSG_PREFIX = '' 

class Message:
    def __init__(self,ptype,pdata):
        self.message_type = ptype;
        self.message_data = pdata;


class Exception(BaseException):
    def __init__(self, s):
        self.s = s
    

class Node(object):
    def __init__(self, reader, writer):
        self.reader = reader
        self.writer = writer
        self._sent_objects = {}
        self._received_objects = {}
        self._received_and_destroyed_ids = []
        self._tied_objects_for_tied_refs = {}

    def close(self):
        if self.reader:
            if self.reader != self.writer:
                self.reader.close
        if self.writer:
            self.writer.close 
        self.reader = None
        self.writer = None

    def send_request_and_receive_response(self, call_type, obj = None, method = None, params = [], opts = None):
        if DEBUG_FLAG: 
            print(RMI.DEBUG_MSG_PREFIX + ": " + str(os.getpid()) 
                + " calling via " + str(self) 
                + " on " + pp.pformat(obj) 
                + ": " + str(method) 
                + " with " + pp.pformat(params)
            )
        
        sendable = [method,0,obj,len(params)]
        for p in params:
            sendable.append(p)

        if not self._send(Message('query',sendable)):
            raise(Exception("failed to send! $!"))

        while True: 
            received = self._receive()
            if DEBUG_FLAG:
                print(RMI.DEBUG_MSG_PREFIX + ": " + str(os.getpid()) + " received" + str(received))
            if received.message_type == 'result': 
                if DEBUG_FLAG:
                    print(RMI.DEBUG_MSG_PREFIX + ": " + str(os.getpid()) + " returning " + str(received.message_data[0]) + "\n")
                return received.message_data[0]
            elif received.message_type == 'close':
                return
            elif received.message_type == 'query':
                self._process_query(received.message_data)
            elif received.message_type == 'exception':
                print(RMI.DEBUG_MSG_PREFIX + ": " + str(os.getpid()) + " caught exception " + pp.pformat(received.message_data))
                raise(Exception(received.message_data))
            else:
                print(RMI.DEBUG_MSG_PREFIX + ": " + str(os.getpid()) + " unexpected message_type " + received.message_type)
                raise(Exception("unexpected message type from RMI message:" % received.message_type))
            
    def receive_request_and_send_response(self):
        received = self._receive()
        
        if received.message_type == 'query':
            response = self._process_query(received.message_data)
            return [received.message_type, received.message_data, response.message_type, response.message_data]
        elif received.message_type == 'close': 
            return;
        else:
            raise(Exception("Unexpected message type " % received.message_type % '!  message_data was:' % pp.pformat(received.message_data)))
        

    def _send(self, message):
        s = self._serialize(message);
        if (DEBUG_FLAG):
            print(DEBUG_MSG_PREFIX + 'N: ' + str(os.getpid()) + " sending: >" + s + "<\n")
        self.writer.write(s)
        self.writer.write("\n")
        self.writer.flush()
        return True

    def _receive(self):
        if (DEBUG_FLAG):
            print(RMI.DEBUG_MSG_PREFIX + ": " + str(os.getpid()) + " receiving\n")

        serialized_blob = None
        try:
            serialized_blob = self.reader.readline()
        except:
            if (DEBUG_FLAG):
                print(DEBUG_MSG_PREFIX + ": " + str(os.getpid()) + " read failure: >\n")

        if (serialized_blob == None):
            # a failure to get data returns a message type of 'close', and undefined message_data
            if (DEBUG_FLAG):
                print(RMI.DEBUG_MSG_PREFIX + ": " + str(os.getpid()) + " connection closed\n")
            self.is_closed = 1
            return(Message('close',undef));

        if (DEBUG_FLAG):
            print(RMI.DEBUG_MSG_PREFIX + ": " + str(os.getpid()) + " got >" + serialized_blob + "<\n")
            if not serialized_blob:
                print("\n")

        message = self._deserialize(serialized_blob);
        return (message);

    def get_dispatcher(self,l):
        # TODO: cache these
        s = 'lambda f,a: f('
        for n in range(0,l):
            s = s + 'a[' + str(n) + ']'
            if n == l-1:
                pass
            else:
                s = s + ','
        s = s + ')'
        #print('s: ' + s)
        f = eval(s)
        return(f)
        
    def testme(a=111,b=222):
        print("hi")
        return(a+b)

    def _process_query(self,message_data):
        method = message_data.pop(0)
        wantarray = message_data.pop(0)
        object = message_data.pop(0)
        nparams = message_data.pop(0)
        
        DEBUG_FLAG=0
        params = []
        processed = 0
        while processed < nparams:
            x = message_data.pop(0)
            params.append(x)
            processed = processed + 1
        
        if DEBUG_FLAG:
            print(RMI.DEBUG_MSG_PREFIX + ": " + str(os.getpid()) + " unserialized method/wantarray/object/params:" + method + '/' + str(wantarray) + '/' + str(object) + '/' + str(params))
        
        executing_nodes.append(self)

        return_type = None
        return_data = None
        try:
            if object != None:
                if DEBUG_FLAG:
                    print(RMI.DEBUG_MSG_PREFIX + ": " + str(os.getpid()) + " call " + method + " on " + str(object))
                method_ref = getattr(object,method)
                if DEBUG_FLAG:
                    print(RMI.DEBUG_MSG_PREFIX + ": " + str(os.getpid()) + " call " + method + " on " + str(object) + " gets result " + str(method_ref)) 
            else:
                pos = method.find('.')
                if pos != -1:
                    pkg = method[:pos]
                    exec('import ' + pkg)
                method_ref = eval(method)
                
                if DEBUG_FLAG:
                    print(RMI.DEBUG_MSG_PREFIX + ": " + str(os.getpid()) + " call " + method + " gets ref" + str(method_ref) + "\n") 
            
            return_data = method_ref(*params)
            return_type = 'result'
            
        except BaseException as e:
            return_data = str(e)
            return_type = 'exception'
            if DEBUG_FLAG:
                #traceback.print_exc(file=sys.stdout)
                print(RMI.DEBUG_MSG_PREFIX + ": " + str(os.getpid()) + " EXCEPTION " + str(e) + "\n") 
            
        if (return_type == 'exception'):
            if (DEBUG_FLAG):
                print(RMI.DEBUG_MSG_PREFIX + ": " + str(os.getpid()) + " executed with EXCEPTION (unserialized): " + pp.pformat(return_data) + "\n")
        else:
            if (DEBUG_FLAG):
                print(RMI.DEBUG_MSG_PREFIX + ": " + str(os.getpid()) + " executed with result (unserialized): " + pp.pformat(return_data) + "\n")
        
        executing_nodes.pop
        
        DEBUG_FLAG=0

        # we MUST undef these in case they are the only references to remote objects which need to be destroyed
        # the DESTROY handler will queue them for deletion, and _send() will include them in the message to the other side
        object = None;
        params = None;
        
        message = Message(return_type, return_data)
        
        self._send(message)
        return(message)
        
    def _is_primitive(self,v):
        if (v == None):
            return True
        elif isinstance(v,str):
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
        return(id[ 1 : (id.find(' object at ')-1) ])
    
    def _id_to_shape(self,id):
        return('unspecified')
        
    def _class_is_proxied(self,c):
        try:
            proxied_classes[c]
            return True
        except KeyError:
            return False

    def _run(ex='',ev='1'):
        if 1:
            exec(ex)
        return eval(ev)

    def _eval(s,cls=None):
        if cls:
            exec('import ' + cls)
        return eval(s)

    def _exec(s):
        return exec(s)
   
    def _serialize(self,message):
        sent_objects = self._sent_objects
       
        #print('serializing: ' + pp.pformat(message) + "\n")
 
        serialized = [ message.message_type, self._received_and_destroyed_ids ]
        self._received_and_destroyed_ids = []
       
        targets = None
        if message.message_type == 'query':
            targets = message.message_data
        else:
            targets = [message.message_data]
 
        for o in targets:
            if self._is_primitive(o):
                serialized.append(0)
                serialized.append(o);
            else:
                if isinstance(o,ProxyObject) or self._class_is_proxied(type(o)):
                    # sending back a proxy, the remote side will convert back to the original value
                    key = None
                    try:
                        local_id = self._object_to_id(o)
                        key = remote_id_for_object[local_id];
                    except: 
                        raise(Exception("no id found for object " + str(o) + '?'))
                        
                    if DEBUG_FLAG:
                        print(RMI.DEBUG_MSG_PREFIX + ": " + str(os.getpid()) + " proxy " + pp.pformat(o) + " references remote " + str(key) + "\n")
                    serialized.append(3)
                    serialized.append(key)
                
                else:
                    # sending an object local to this side, the remote side will convert to 
                    # TODO: use something better than stringification since this can be overridden!!!
                    id = self._object_to_id(o)
                    
                    #if self.allow_packages:
                    #    if not self.allowed[type(o)]:
                    #        raise(Exception("objects of type " + str(type(o)) + " cannot be passed from this RMI node!"))
                    
                    serialized.append(1)
                    serialized.append(id)
                    sent_objects[id] = o;

        if DEBUG_FLAG:
            print(RMI.DEBUG_MSG_PREFIX + ": " + str(os.getpid()) + " $message_type translated for serialization to @serialized\n")

        message_data = None # essential to get the DESTROY handler to fire for proxies we're not holding on-to
 
        if DEBUG_FLAG:
            print(RMI.DEBUG_MSG_PREFIX + ": " + str(os.getpid()) + " destroyed proxies: @$received_and_destroyed_ids\n")        
       
        serialized_blob = pp.pformat(serialized)
        serialized_blob.replace("\n",' ') 
        #print('BLOB:' + serialized_blob)
        
        if DEBUG_FLAG:
            print(RMI.DEBUG_MSG_PREFIX + ": " + str(os.getpid()) + " " + str(message.message_type) + " serialized as " + serialized_blob)
        
        if serialized_blob.find('\n') != -1:
            raise(Exception("newline found in message data!"))
            pass

        return serialized_blob
        
    def _deserialize(self,serialized_blob):
        if DEBUG_FLAG:
            print(RMI.DEBUG_MSG_PREFIX + ": " + str(os.getpid()) + " processing (serialized): " + pp.pformat(serialized_blob))
        
        serialized = eval(serialized_blob)
        message_type = serialized.pop(0)
        if message_type == None:
            raise(Exception("unexpected undef type from incoming message: " + serialized_blob))

        received_and_destroyed_ids  = serialized.pop(0)

        sent_objects                = self._sent_objects
        received_objects            = self._received_objects
        
        message_data = []
        while (len(serialized)):
            vtype = serialized.pop(0)
            
            if DEBUG_FLAG:
                print(RMI.DEBUG_MSG_PREFIX + ": " + str(os.getpid()) + " processing item: " + str(vtype))

            if (vtype == 0):
                # primitive value
                value = serialized.pop(0)
                if DEBUG_FLAG:
                    print(RMI.DEBUG_MSG_PREFIX + ": " + str(os.getpid()) + " - primitive " + str(value) + "\n")
                message_data.append(value)
                
            elif (vtype == 1 or vtype == 2):
                # an object exists on the other side: make a proxy unless we already have one
                # note that type 2 is for Perl non-object references, which Python doesn't ever generate, but may receive
                remote_id = serialized.pop(0)
                try:
                    o = received_objects[remote_id]
                except KeyError:
                    # no proxy for this id yet...
                    remote_class = self._id_to_class(remote_id)
                    remote_shape = self._id_to_shape(remote_id)
                    
                    o = None
                    if remote_shape == 'ARRAY':
                        o = ProxyObject(self,remote_id)
                    elif remote_shape == 'HASH':
                        o = ProxyObject(self,remote_id)
                    elif remote_shape == 'CODE':
                        o = lambda params: self.send_request_and_receive_response('call_coderef', None, 'RMI.Node._exec_coderef', [remote_id, params])
                    else:
                        o = ProxyObject(self,remote_id)
                    
                    received_objects[remote_id] = weakref.ref(o)
                    local_id = self._object_to_id(o)
                    node_for_object[local_id] = self;
                    remote_id_for_object[local_id] = remote_id;
                
                message_data.append(o)
                if DEBUG_FLAG:
                    print(RMI.DEBUG_MSG_PREFIX + ": " + str(os.getpid()) + " - made proxy for " + remote_id  + "\n")
            
            elif (vtype == 3):
                # exists on this side, and was a proxy on the other side: get the real reference by id
                local_id = serialized.pop(0)
                try:
                    o = sent_objects[local_id] 
                except:
                    print(RMI.DEBUG_MSG_PREFIX + ": " + str(os.getpid()) + " reconstituting local object $value, but not found in my sent objects!\n")
                    raise
                message_data.append(o)
                if DEBUG_FLAG:
                    print(RMI.DEBUG_MSG_PREFIX + ": " + str(os.getpid()) + " - resolved local object " + str(o) + " for value " + local_id)
            else:
                raise(Exception("Unknown type in serialized data!"))        

        if DEBUG_FLAG:
            print(RMI.DEBUG_MSG_PREFIX + ": " + str(os.getpid()) + " remote side destroyed: @$received_and_destroyed_ids\n")

        missing = []
        for id in received_and_destroyed_ids:
            found = sent_objects[id]
            if found:
                del sent_objects[id]
            else:
                missing.append(id)
        if len(missing) > 0:
            print("Some IDS not found in the sent list: done: @done, expected: @$received_and_destroyed_ids\n")
        
        return(Message(message_type,message_data))
        
    def _exec_coderef(code,args):
        return code(*args)
        '''
        my $sub_id = shift;
        my $sub = $RMI::executing_nodes[-1]{_sent_objects}{$sub_id};
        die "$sub is not a CODE ref.  came from $sub_id\n" unless $sub and ref($sub) eq 'CODE';
        goto $sub;
        '''
        
    def bind_local_var_to_remote():
        raise(Exception(__LINE__))
    
    def bind_local_class_to_remote():
        raise(Exception(__LINE__))
    
    def _remote_has_ref():
        raise(Exception(__LINE__))
        '''
        my ($self,$obj) = @_;
        my $id = "$obj";
        my $has_sent = $self->send_request_and_receive_response('call_eval', undef, "RMI::Server::_receive_eval", ['exists $RMI::executing_nodes[-1]->{_received_objects}{"' . $id . '"}']);
        '''
        
    def _remote_has_sent():
        raise(Exception(__LINE__))
        '''
        my ($self,$obj) = @_;
        my $id = "$obj";
        my $has_sent = $self->send_request_and_receive_response('call_eval', undef, "RMI::Server::_receive_eval", ['exists $RMI::executing_nodes[-1]->{_sent_objects}{"' . $id . '"}']);
        '''

class Client(RMI.Node):
    def call_function():
        raise(Exception(__LINE__))
    def call_class_method():
        raise(Exception(__LINE__))
    def call_object_method():
        raise(Exception(__LINE__))
    def call_eval():
        raise(Exception(__LINE__))
    def call_use():
        raise(Exception(__LINE__))
    def call_use_lib():
        raise(Exception(__LINE__))
    def use_remote():
        raise(Exception(__LINE__))
    def use_lib_remote():
        raise(Exception(__LINE__))
    def virtual_lib():
        raise(Exception(__LINE__))
    def bind():
        raise(Exception(__LINE__))

class Client(Node):
    class ForkedPipes(Client):
        def __init__(self):
            (client_reader, server_writer) = os.pipe()
            (server_reader, client_writer) = os.pipe()

            if not os.fork():
                # the child process starts a server and exits when done
                RMI.DEBUG_MSG_PREFIX = '    SERVER'
                #RMI.DEBUG_FLAG = 1
                server_reader = os.fdopen(server_reader, 'r')
                server_writer = os.fdopen(server_writer, 'w')
                s = RMI.Node(reader = server_reader, writer = server_writer)

                # the server should return fals whenever a client disconnects
                # somehow it just hangs :( 
                # we need to fix this
                response = s.receive_request_and_send_response()
                while (response):
                    if response[3] == 'exitnow':
                        response = None
                    else:
                        response = s.receive_request_and_send_response()
                print("SERVER DONE")
                exit()

            else:
                # the parent process initializes as the client and continues
                RMI.DEBUG_MSG_PREFIX = 'CLIENT'
                #RMI.DEBUG_FLAG = 1 
                client_reader = os.fdopen(client_reader, 'r')
                client_writer = os.fdopen(client_writer, 'w')
                RMI.Client.__init__(self,client_reader,client_writer)

class Server:
    def __init__(self):
        raise(Exception(__LINE__))
    def run():
        raise(Exception(__LINE__))
    def _receive_use():
        raise(Exception(__LINE__))
    def _receive_use_lib():
        raise(Exception(__LINE__))
    def _receive_eval():
        raise(Exception(__LINE__))

class Wrap:
    def delegate(self,method,*args):
        node = None
        try:
            local_id = str(self)
            node = node_for_object[local_id]
        except KeyError: 
            print("no node for object?! " + str(self))
            raise
        response = node.send_request_and_receive_response('call_object_method', self, method, args);
        return response


class ProxyMeta:
    def __init__(self):
        pass

class ProxyObject:
    __metaclass__ = RMI.ProxyMeta
    
    def __init__(self,node,remote_id):
        pass

    # Basically every method call will attempt to find the method
    # reference in the object's symbol table.  We return a wrapper
    # on demand, which ends up being called.
    # This means we never really go through the "call_object_method" interface
    # except to go to 
    def __getattr__(self,attr):
        node = None
        try:
            local_id = str(self)
            node = node_for_object[local_id]
        except KeyError: 
            print("no node for object?! " + str(self))
            raise
        response = node.send_request_and_receive_response('call_function', None, 'getattr', [self,attr]);
        return response

    # Some methods which implement standard language functionality are "special", and won't be
    # seen by __getattr__ above.  We need to catch these calls and delegate them across the connection.

    def __call__(self, *args):
        return RMI.Wrap.delegate(self,'__call__',*args)
        #delegate = self.__getattr__('__call__');
        #return delegate(*args,**kwargs)
    
    def __len__(self,*args,**kwargs):
        return RMI.Wrap.delegate(self,'__len__',*args)

    def __getitem__(self,*args):
        return RMI.Wrap.delegate(self,'__getitem__',*args)
    
    def can():
        raise(Exception(__LINE__))
    
    def isa():
        raise(Exception(__LINE__))

    def DESTROY():
        raise(Exception(__LINE__))


