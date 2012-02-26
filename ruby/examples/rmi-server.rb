#!/usr/bin/env ruby 
require 'rmi/server/tcp'
s = RMI::Server::Tcp.new(:port => 1234) 
s.run
