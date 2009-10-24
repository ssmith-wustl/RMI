#!/usr/bin/env python

import os
import posix
import RMI
import F1
import F2

test_pass = 0
test_fail = 0

def note(s=''):
    print("# " + s)

def ok(b=None,m=None):
    if b:
        if m:
            print("ok " + m)
        else:
            print("ok got" + str(b))
        #test_pass = test_pass + 1
        return 1 

    else:
        if m:
            print("NOK " + m)
        else:
            print("NOK got" + str(b))
        #test_fail = test_fail + 1
        return 0 

def is_ok(a,b,m=None):
    if not m:
        m = 'comparing ' + str(a) + ' to expected ' + str(b)
    try:
        if ok(a==b,m):
            return 1  
        else:
            print("#\tgot " + str(a) + " expected " + str(b))
            return 0
    except:
        print("NOK " + m)
        print("#\tuncomparable types for! " + str(a) + " expected " + str(b))
        #test_fail = test_fail + 1
        return 0

def ok_show(b,m=''):
    m = m + " (" + str(b) + ")"
    return ok(b,m)

(client_reader, server_writer) = os.pipe()
ok(client_reader, 'made client to server pipe')

(server_reader, client_writer) = os.pipe()
ok(client_reader, 'made server to client pipe')

client_reader = os.fdopen(client_reader, 'r')
server_reader = os.fdopen(server_reader, 'r')
client_writer = os.fdopen(client_writer, 'w')
server_writer = os.fdopen(server_writer, 'w')

ok(client_reader)
ok(client_writer)
ok(server_reader)
ok(server_writer)

c = RMI.Node(reader = client_reader, writer = client_writer)
ok(c)

s = RMI.Node(reader = server_reader, writer = server_writer)
ok(s)

def addo(a,b):
    return(a+b)

def getarray():
    return([111,222,333]);

if os.fork():
    #RMI.DEBUG_FLAG = 1
    RMI.DEBUG_MSG_PREFIX = '    SERVER'

    #print("...");
    response = s.receive_request_and_send_response()
    while (response):
        if response[3] == 'exitnow':
            response = None
        else:
            #print("...");
            response = s.receive_request_and_send_response()

    print("SERVER DONE")
    exit();
    
else:
    #RMI.DEBUG_FLAG = 1 
    RMI.DEBUG_MSG_PREFIX = 'CLIENT'

    r = c.send_request_and_receive_response('call_function', None, 'RMI.Node._eval', ['2+3']);
    is_ok(r,5,'result of remote eval of 2+3 is 5')

    sum1 = c.send_request_and_receive_response('call_function', None, '__main__.addo', [7,8])
    is_ok(sum1,15,'result of remote function call __main__.addo(7,8) works')    

    sum2 = c.send_request_and_receive_response('call_function', None, 'F1.add', [4,5]);
    ok(sum2, 'remote function call with primitives works')

    val3 = F1.x1()
    is_ok(val3,11,'result of local functin call to plain function works')

    local1 = F1.C1();
    ok_show(local1, 'local constructor works')
    if local1:
        ok_show(local1.foo, 'local object property access works')

    remote1 = c.send_request_and_receive_response('call_function', None, 'F1.echo', [local1]);
    is_ok(remote1, local1, 'remote function call with object echo works')

    note("test returning an array")
    remote2 = c.send_request_and_receive_response('call_function', None, '__main__.getarray', []);
    ok_show(remote2, 'got a result, hopefully an array');
    value = remote2[0]
    ok_show(value, "got a value from the proxy array");
    ok_show(str(remote2[0]), "got value 1");
    ok_show(str(remote2[1]), "got value 2");
    ok_show(str(remote2[2]), "got value 3");

    note("test returning a usable lambda expression with zero params");
    remote4 = c.send_request_and_receive_response('call_function', None, 'RMI.Node._eval', ['lambda: 555']);
    ok(remote4 != None, 'remote lambda construction works')
    val2 = remote4()
    is_ok(val2,555,"remote lambda works with zero params")

    note("test returning a usable lambda expression with two params");
    remote3 = c.send_request_and_receive_response('call_function', None, 'RMI.Node._eval', ['lambda a,b: a+b']);
    ok(remote3 != None, 'remote lambda construction works with params')
    val3 = remote3(6,2)
    is_ok(val3,8,"remote lambda works with params")

    # Somehow, closing the connection doesn't cause the server to catch the close, so we have a hack to
    # signal to it that it should exit.  Fix me.
    c.close
    c.send_request_and_receive_response('call_function', None, 'RMI.Node._eval', ['"exitnow"']);
    print("CLIENT DONE")
    
'''    

  
    remote2 = c.send_request_and_receive_response('call_function', None, 'F1.C1');
    ok(remote2, "got remote obj")
 
    exit

    if remote2:
        val2 = remote2.m1()
        is_ok(val2,"456","remote method call returns as expected")
        ref2 = remote2.m1
        ok(ref2,"remote method ref is as expected")
        val2b = ref2()
        is_ok(val2b,"456","remote methodref returns as expected")

    zz = c.send_request_and_receive_response('call_function', None, 'RMI.Node._eval', ['z']);
    print('zz: ' + str(zz))

    imp = c.send_request_and_receive_response('call_function', None, 'RMI.Node._e', [1,'import F1'])
    print('imp: ' + str(imp))

    f1c = c.send_request_and_receive_response('call_function', None, 'RMI.Node._e', [2, 'F1.x1()'])
    print('f1b: ' + str(f1c))
'''
  
    
       
'''
exit


if os.fork():
     service one request and exit
    exit

# send one request and get the result

    
# we might have also done..
#robj = c->send_request_and_receive_response('call_class_method', 'IO::File', 'new', '/my/file');

# this only works on objects which are remote proxies:
#$txt = $c->send_request_and_receive_response('call_object_method', $robj, 'getline');
   
def ok(result,message):
    if result:
        print('ok  ' + message)
    else:
        print('NOK ' + message)

ok(1, "hello")
ok(0, "goodbye")
'''
    
