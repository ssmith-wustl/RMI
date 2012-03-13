#!/usr/bin/env ruby 
require "test/unit"
require "rmi"
require "rmi/client/forked-pipes"

class Test99 < Test::Unit::TestCase
    def test_local_block_remote_array
        client = RMI::Client::ForkedPipes.new()
        
        local_array = [11,22,33] 
        remote_array = client.call('eval','[11,22,33]')
       
        # test a plain block with the local and remote array
        
        @@sum = 0
        local_array.each do |value|
            @@sum += value
        end
        assert_equal(@@sum, 11+22+33, "successfully passed a block to each() for a local array")
        
        @@sum = 0
        remote_array.each do |value|
            @@sum += value
        end
        assert_equal(@@sum, 11+22+33, "successfully passed a block to each() for a remote array")

        # now try the same with a local proc

        @@sum = 0
        local_proc = Proc.new { |value| @@sum += value }
        remote_proc = client.call('eval','Proc.new { |value| @@sum += value }')

        @@sum = 0
        local_array.each &local_proc 
        assert_equal(@@sum, 11+22+33, "successfully passed a local proc to each() for a local array")
        
        @@sum = 0
        #remote_array.each &local_proc
        #assert_equal(@@sum, 11+22+33, "successfully passed a local proc to each() for a remote array")

    end
end
