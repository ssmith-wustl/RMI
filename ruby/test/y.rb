
require 'rmi'
require 'rmi/client/forked-pipes'
require 'rmi/client/tcp'

c = RMI::Client::Tcp.new(:port => 1234)

p1a = Proc.new do |x,y| print "#{x*y}\n"; x*y; end
p1b = Proc.new do |*a| print "#{a[0]*a[1]}\n"; a[0]*a[1]; end

p2a = c.call('eval', 'Proc.new do |x,y| print "#{x*y}\n"; x*y; end')
#p2b = c.call('eval', 'Proc.new do |*a| print "#{a[0]*a[1]}\n"; a[0]*a[1]; end')

print "arity local: ", p1a.arity, "\narity remote:", p2a.arity,"\n"

#z = p1.call(5,6)
#print "local proc call #{z}\n"

z = p2a.call(5,6)
print "remote proc call #{z}\n"

#[ [11,3], [22,3], [33,3] ].each do |a,b|
#    z = p2.call(a,b)
#end

#print "\n"

#[ [11,3], [22,3], [33,3] ].each &p1a
#[ [11,3], [22,3], [33,3] ].each &p1b
[ [11,3], [22,3], [33,3] ].each &p2a
#[ [11,3], [22,3], [33,3] ].each &p2b



