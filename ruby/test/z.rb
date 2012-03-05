
require 'rmi'
require 'rmi/client/forked-pipes'
require 'rmi/client/tcp'

c = RMI::Client::Tcp.new(:port => 1234)

p1 = Proc.new do |a,b,*c| [a,b,c.join(":")].join(",");  end
p2 = c.call('eval', 'Proc.new do |a,b,*c| [a,b,c.join(":")].join(",");  end')

print "arity local: ", p1.arity, "\narity remote:", p2.arity,"\n"

z = p1.call(11,22,33,44,55)
print "local proc call #{z}\n"

z = p2.call(11,22,33,44,55)
print "remote proc call #{z}\n"


