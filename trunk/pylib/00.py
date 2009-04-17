#!/Library/Frameworks/Python.framework/Versions/3.0/bin/python
#!/usr/bin/env python

import os
import posix
import RMI
import F1

def ok(b,m=None):
    if b:
        if m:
            print("ok\t" + m)
        else:
            print("ok\tgot" + str(b))
        return(1)

    else:
        if m:
            print("NOK\t" + m)
        else:
            print("NOK\tgot" + str(b))
        return(0)

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
else:
    r = c.send_request_and_receive_response('call_function', None, 'RMI.Node._eval', ['2+3']);
    print('r: ' + str(r))

    sum = c.send_request_and_receive_response('call_function', None, '__main__.addo', [7,8])
    print('sum: ' + str(sum))

    f1a = F1.x1()
    print('f1a: ' + str(f1a))

    o = F1.C1();
    print(str(o))
    print('f1a a1' + str(o.a1));   
    print('f1a m1' + str(o.m1));   
    print('f1a foo' + str(o.foo));   
 
    obj1 = c.send_request_and_receive_response('call_function', None, 'RMI.Node._eval', ['lambda a,b: a+b']);
    print('result 1, remote lambda: ' + str(obj1))

    obj2 = c.send_request_and_receive_response('call_function', None, 'F1.add', [4,5]);
    print('result 2, remote function call with primitives: ' + str(obj2))

    obj3 = c.send_request_and_receive_response('call_function', None, 'F1.C1');
    print('obj: ' + str(obj3))

    print(obj3.m1())

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
    
