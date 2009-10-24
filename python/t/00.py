#!/usr/bin/env python

import os
import posix
import RMI
import F1
import F2

test_pass = 0
test_fail = 0

# these are a cheap attempt to imitate Perl's Test::More simplicity
# TODO: convert to xUnit

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

# test functions


def addo(a,b):
    return(a+b)

def getarray():
    return([111,222,333]);

# make a pair of forked pipes
c = RMI.Client.ForkedPipes()
ok(c, "got forked pipe client");

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
    ok_show(local1.m1, 'local object property access works')

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

note("testing returning a remote object from a function")
remote5 = c.send_request_and_receive_response('call_function', None, 'F1.C1',[]);
val2 = remote5.m1()
is_ok(val2,"456","remote method call returns as expected")
#c.send_request_and_receive_response('call_function', None, 'RMI.Node._eval', ['RMI.DEBUG_FLAG']);

ref2 = remote5.__getattr__('m1')
ok(ref2 != None,"remote method ref is as expected")
print(RMI.pp.pformat(ref2));
val2b = ref2()
is_ok(val2b,"456","remote methodref returns as expected")

zz = c.send_request_and_receive_response('call_function', None, 'RMI.Node._eval', ['"z"']);
print('zz: ' + str(zz))

f1c = c.send_request_and_receive_response('call_function', None, 'RMI.Node._eval', ['F1.x1()'])
print('f1b: ' + str(f1c))

imp = c.send_request_and_receive_response('call_function', None, 'RMI.Node._eval', ['import F1'])
print('imp: ' + str(imp))

# Somehow, closing the connection doesn't cause the server to catch the close, so we have a hack to
# signal to it that it should exit.  Fix me.
c.close
c.send_request_and_receive_response('call_function', None, 'RMI.Node._eval', ['"exitnow"']);
print("CLIENT DONE")
    
'''    

  

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
    
