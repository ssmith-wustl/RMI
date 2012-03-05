
require 'rmi'
require 'rmi/client/forked-pipes'
require 'rmi/client/tcp'

c = RMI::Client::Tcp.new(:port => 1234)

p1b = Proc.new do |a| print "#{a[0]*a[1]}\n"; a[0]*a[1]; end

p2b = c.call('eval', 'Proc.new do |a| print "#{a[0]*a[1]}\n"; a[0]*a[1]; end')

print "arity local: ", p1b.arity, "\narity remote:", p2b.arity,"\n"

z = p1b.call([5,6])
print "local proc call #{z}\n"

z = p2b.call([5,6])
print "remote proc call #{z}\n"

#[ [11,3], [22,3], [33,3] ].each do |a,b|
#    z = p2.call(a,b)
#end

#print "\n"

[ [11,3], [22,3], [33,3] ].each &p1b
[ [11,3], [22,3], [33,3] ].each &p2b



