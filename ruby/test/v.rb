#!/usr/bin/env ruby 
require "rmi"
require "rmi/client/forked-pipes"
require "rmi/client/tcp"

n6 = RMI::Client::Tcp.new(:port => 1234)
a = n6.call('eval','[11,22,33]')
t = 0
a.each do |v|
    t += v
end
print t,"\n"

