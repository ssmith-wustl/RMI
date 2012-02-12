#!/usr/bin/env ruby
require 'rmi/client/tcp'

c = RMI::Client::Tcp.new(
    host => 'localhost', 
    port => 1234
)

r = c.call_eval("2+3")
print r,"\n"


=begin

c.call_use('IO::File'); 

r = c.call_class_method('IO::File','new','/etc/passwd');

line1 = $r->getline;           # works as an object

line2 = <$r>;                  # works as a file handle
rest  = <$r>;                  # detects scalar/list context correctly

r->isa('IO::File');            # transparent in standard ways
r->can('getline');

ref($r) eq 'RMI::ProxyObject';  # the only sign this isn't a real IO::File...
                # (see RMI::Client's use_remote() to fix this)

=end

