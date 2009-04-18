#!/usr/bin/env python

import os
import posix
import RMI
import F1

test_pass = 0
test_fail = 0

def ok(b,m=None):
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

if os.fork():
    s.receive_request_and_send_response();
    s.receive_request_and_send_response();
    s.receive_request_and_send_response();
    s.receive_request_and_send_response();
    s.receive_request_and_send_response();
    s.receive_request_and_send_response();
    s.receive_request_and_send_response();
    s.receive_request_and_send_response();
    s.receive_request_and_send_response();
    s.receive_request_and_send_response();
    
else:
    RMI.DEBUG_FLAG = 1
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

    remote2 = c.send_request_and_receive_response('call_function', None, 'F1.C1');
    ok(remote2, 'remote object construction works')
    
    if remote2:
        val2 = remote2.m1()
        is_ok(val2,"456","remote method call returns as expected")

    remote3 = c.send_request_and_receive_response('call_function', None, 'RMI.Node._eval', ['lambda a,b: a+b']);
    ok_show(remote3, 'remote lambda construction works')

    if remote3:
        val3 = remote3(6,2)
        is_ok(val3,8,"remote lambda works")

'''    
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
    
