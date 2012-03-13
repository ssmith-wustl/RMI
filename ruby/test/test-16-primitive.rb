#!/usr/bin/env ruby 
require "rmi"
require "rmi/client/forked-pipes"
require "test/unit"

class Test15 < Test::Unit::TestCase
    def test_primitives
        client = RMI::Client::ForkedPipes.new()
        remote_array = client.call('eval','[11,"hello",nil,true,false]')

        #local_copy = [*remote_array]
        
        local_copy = []
        remote_array.length.times do |n|
            local_copy[n] = remote_array[n]
        end

        assert_equal(local_copy[0], 11)
        assert_equal(local_copy[1], "hello")
        assert_equal(local_copy[2], nil)
        assert_equal(local_copy[3], true)
        assert_equal(local_copy[4], false)
        
        assert_equal("#{local_copy[0]}", "11")
        assert_equal("#{local_copy[1]}", "hello")
        assert_equal("#{local_copy[3]}", "true")
        assert_equal("#{local_copy[4]}", "false")
    end
end

