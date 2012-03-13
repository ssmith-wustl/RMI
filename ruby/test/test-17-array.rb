#!/usr/bin/env ruby 
require "rmi"
require "rmi/client/forked-pipes"
require "test/unit"
#require "rmi/proxyobject/array"

class Test15 < Test::Unit::TestCase
    def test_primitives
        client = RMI::Client::ForkedPipes.new()
        remote_array = client.call('eval','[11,22,33]')

        local_copy1 = [11,22,33].to_a
        print "#{local_copy1}\n"
        
        local_copy2 = remote_array.to_a
        print "#{local_copy2}\n"
        
        local_copy3 = [*local_copy1]
        print "#{local_copy3}\n"
    end
end

