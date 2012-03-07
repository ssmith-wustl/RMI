#!/usr/bin/env ruby

require "test/unit"
$:.unshift File.dirname(__FILE__) + '/lib'
require "testclass2"
require "rmi/client/forked-pipes"
require "rmi/client/tcp"


class Test02 < Test::Unit::TestCase
    def note(s) 
        print s,"\n"
    end

    def test_simple
        c = RMI::Client::ForkedPipes.new()
        #c = RMI::Client::Tcp.new(:port => 1234)
        assert(c, "created an RMI::Client::ForkedPipes using the default constructor (fored process with a pair of pipes connected to it)")
      
        #b = c.call('eval', 'Proc.new { |x| print "XX: #{x}\n" }')
        #print "GOT BLOCK #{b}\n"
      
        #bb = Proc.new { |x| print "XX: #{x}\n" }
        #[11,22,33].each &b

        #exit;

        c.call('eval', "$:.unshift File.dirname(__FILE__) + '/lib'")
        c.call('require', 'testclass2')

        note("make a remote object")
        remote1 = c.call('class_method', 'RMI::TestClass2', 'new')
        assert(remote1, "got an object")


        a = remote1.create_and_return_arrayref('one', 111, 'two', 222)
        b = [a[0],a[1],a[2],a[3]]

        #b.each { |e| print "E: #{e}\n" }
        assert(b.kind_of?(Array), "object #{a} is an Array")
    end
end

=begin



###################


a = eval { a };
assert(!, "treated returned value as an arrayref")
is("a", "one 111 two 222", " content is as expected")

a2 = remote1.last_arrayref
is(a2,a, "2nd copy of arrayref a2 from the remote side matches he first a")

push a, three => 333
is(a.[4],"three", "successfully mutated array with push")
is(a.[5],"333", "successfully mutated array with push")
is(remote1.last_arrayref_as_string(), "one:111:two:222:three:333", " contents on the remote side match")

a.[3] = '2222'
is(a.[3],'2222',"updated one value in the array")
is(remote1.last_arrayref_as_string(), "one:111:two:2222:three:333", " contents on the remote side match")

v2 = a.pop
is(v2,'333',"works").pop
v1 = a.pop
is(v1,'three',"works.pop again")
is(remote1.last_arrayref_as_string(), "one:111:two:2222", " contents on the remote side match")

eval { a = (11,22) }
assert(!$@, "reset of the array contents works (preivously a bug b/c Tie::StdArray has no implementation of EXTEND.")
    or diag()


###################

note("test returned non-object references: HASH")

h = remote1.create_and_return_hashref(one => 111, two => 222)
isa_assert(h,"HASH", "object h is a HASH")

h = eval { %h };
assert(!, "treated returned value as an hashref")
is("h", "one 111 two 222", " content is as expected")

h.{three} = 333
is(h.{three},333,"key addition")

h.{two} = 2222
is(h.{two},2222,"key change works")

assert(exists(h.{one}), "key exists before deletion")
v = delete h.{one}
is(v,111,"value returns from deletion")
assert(!exists(h.{one}), "key is gone after deletion")

is(remote1.last_hashref_as_string(), "three:333:two:2222", " contents on the remote side match")

###################

note("test returned non-object references: SCALAR")

s = remote1.create_and_return_scalarref("hello")
isa_assert(s,"SCALAR", "object h is a SCALAR")
v3 = #{}s
is(v3,"hello", "scalar ref returns correct value")
#{}s = "goodbye"
v4 = remote1.last_scalarref_as_string()
is(v4,"goodbye","value of scalar on remote side is correct")

###################

note("test returned non-object references: CODE")

x = remote1.create_and_return_coderef('sub { r = #{} return join(":",r,_); }');
isa_assert(x,"CODE", "object h is a CODE reference")
v5 = x.()
is(v5, c.peer_id, "value returned is as expected")
v6 = x.('a','b','c')
is(v6, c.peer_id + ":a:b:c", "value returned from second call is as expected")
x = undef

note("Test passing code refs")
a1 = (11,22,33)
my $sub1 = sub {
    for (@a1) {
        _ *= 2
    }
end
remote1.call_my_sub(sub1)
is_deeply(\a1,[22,44,66], "remote server called back local sub and modified closure variables")

###################

note("closing connection")
c.close
note("exiting")
exit

=end

