#!/usr/bin/env python
import RMI
x = RMI.Node()
print(x)

d = x._get_dispatcher_for_param_list_length(2)
f = lambda a,b: a+b
a = [5,3]
r = d(f,a)
print(r)
