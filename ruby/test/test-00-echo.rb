#!/usr/bin/env ruby 

require 'rmi'
require 'rmi/client/forked-pipes'
require 'test/unit'

module Test1
    def self.echo(s)
        return s
    end
end

class Foo
end

class Test00 < Test::Unit::TestCase
    def setup 
        @c = RMI::Client::ForkedPipes.new()
        @o1 = Foo.new() 
        @h1 = { :foo => 111 }
    end
    
    def test_construction
        assert(@c, "created a test client/server pair");
        
        assert(@o1, "created dummy object of type Foo");
        assert(@h1, "created dummy hash");
    end

    def test_calls
        v = '12345';
        v2 = @c.call('function','Test1::echo', v)
        assert_equal(v2,v)

        o2 = @c.call('function','Test1::echo', @o1)
        assert_equal(o2, @o1, "the returned object is the same as the sent one")

        @h1 = { :foo => 111 }
        h2 = @c.call('function','Test1::echo',@h1)
        assert_equal(h2, @h1, "the returned reference is the same as the sent one")
    end
end

