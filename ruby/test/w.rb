#!/usr/bin/env ruby 
require "rmi"
require "rmi/client/forked-pipes"
require "rmi/client/tcp"

n6 = RMI::Client::Tcp.new(:port => 1234)

a = n6.call('eval','[11,22,33]')
#a2 = [11,22,33]

p = n6.call('eval','Proc.new { |e| print ">> #{e}\n" }')
p2 = Proc.new { |e| print ">>#{e}\n" }

class WR < Proc
end

p3 = WR.new do |e| print ">>> #{e}\n" end

#e = a2.each do |e|
#    print ">> #{e}\n"
#end
e = a.each(&p2)

print "retval from each is #{e}\n"
#assert_equal(a.length, 3, "got 3 item array")

