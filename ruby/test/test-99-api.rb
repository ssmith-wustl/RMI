#!/usr/bin/env ruby 

require "rmi"
require "test/unit"
require "set"

class Test99 < Test::Unit::TestCase
    def test_node_constructor_params
        assert_nothing_raised do
            n1 = RMI::Node.new(:writer => 123)
        end
        
        assert_raise ArgumentError do
            n2 = RMI::Node.new(:junk => 123)
        end 
        
        assert_raise ArgumentError do
            n2 = RMI::Node.new(:local_language => 'perl')
        end
    end

    def test_default_properties
        n3 = RMI::Node.new(:remote_language => 'perl5')
        assert_equal(n3.local_language, 'ruby');
        assert_equal(n3.remote_language, 'perl5');

        n4 = RMI::Node.new(:allow_modules => ['a','b','c']);
        assert(n4.allow_modules.include?('a'))
        assert(n4.allow_modules.include?('c'))
        assert(!n4.allow_modules.include?('xxxx'))
    end

    def test_eval 
        require "rmi/client/forked-pipes"
        n5 = RMI::Client::ForkedPipes.new()
        a = n5.call('eval',"2+3")
        assert_equal(a, 5, "basic eval returning primitives works")
    end

    def test_remote_array
        require "rmi/client/forked-pipes"
        n6 = RMI::Client::ForkedPipes.new()
        a = n6.call('eval','[11,22,33]')
        t = 0
        e = a.each do |v|
            t += v
        end
        assert_equal(t, 11+22+33, 'can iterate over remote array and call local block')
    end
end

