package RMI;

use strict;
use warnings;
use version;
our $VERSION = qv('0.03');

# the whole base set of classes which make general RMI work
# (sub-classes of RMI Server & Client provide specific implementations such as sockets, etc.)
use RMI::Node;
use RMI::Client;
use RMI::Server;
use RMI::ProxyObject;
use RMI::ProxyReference;

our @executing_nodes; # required for some methods on the remote side to find the RMI node acting upon them
our %proxied_classes; # tracks classes which have been fully proxied into this process by some client

# turn on debug messages if an environment variable is set
our $DEBUG;
BEGIN { $RMI::DEBUG = $ENV{RMI_DEBUG}; };

# this is used at the beginning of each debug message
# setting it to a single space for a server makes server/client distinction
# more readable in combined output.
our $DEBUG_MSG_PREFIX = '';

=pod

=head1 NAME

RMI - Remote Method Invocation with transparent proxies

=head1 SYNOPSIS

 #process 1: an example server on host "myserver"

    use RMI::Server::Tcp;
    my $s = RMI::Server::Tcp->new(port => 1234); 
    $s->run;


 #process 2: an example client

    use RMI::Client::Tcp;
    my $c = RMI::Client::Tcp->new(
       host => 'myserver', 
       port => 1234,
    );

    $c->call_use('IO::File'); 
    $r = $c->call_class_method('IO::File','new','/etc/passwd');

    $line1 = $r->getline;           # works as an object

    $line2 = <$r>;                  # works as a file handle
    @rest  = <$r>;                  # detects scalar/list context correctly

    $r->isa('IO::File');            # transparent in standard ways
    $r->can('getline');
    
    ref($r) eq 'RMI::ProxyObject';  # the only sign this isn't a real IO::File...
				     # (see use_remote() to fix this)

=head1 DESCRIPTION

RMI stands for Remote Method Invocation.  The RMI modules allow one Perl
process to have virtual objects which are proxies for a real object
in another process.  When methods are invoked on the proxy, the method
actually runs in the other process.  When results are returned, those
values are also proxies for the real items in the other process.

In addition to invoking methods on proxy objects trasparently, an RMI::Client
can invoke class methods, regular function calls, and other Perl functionaity 
on the remote server.  Calls like these are typically the first step to obtain 
a remote object in the first place.

The procedure typically goes as follows:

1. a server is started which has access to some objects or data which is of value
 
2. a client connects to that server, and asks that it execute code on its behalf
 
3. the results returned may contain objects or other references,
which the client recieves as proxies which "seem like" the real thing

4. further interaction with the returned proxy objects/refs automatically
make calls through the client to the server internally

=head1 METHODS

The RMI module has no public methods of its own.

See B<RMI::Client> and B<RMI::Server> for detailed API information and examples.

See B<RMI::ProxyObject> and B<RMI::ProxyReference> for details on behavior of
proxies.

See B<RMI::Node> for internals and details on the wire protocol.

=head1 IMPLEMENTATIONS IN OTHER LANGUAGES

The use of transparent proxy objects goes by the term "RMI" in Java, "Drb"
in Ruby, "PYRO" in Python, "Remoting" in .NET, and is similar in functionality
to architectures such as CORBA, and the older DCOM.

None of the above use the same protocols (except Java's RMI has an optional
CORBA-related implementation).  This module is no exception, sadly.  Patches 
are welcome.

=head1 PROXY OBJECTS AND REFERENCES

A proxy object is an object on one "side" of an RMI connection which represents
an object which really exists on the other side.  When an RMI::Client calls a
method on its associated RMI::Server, and that method returns a reference of any
kind, including an object, a proxy is made on the client side, rather than a
copy.  The proxy object appears to be another reference to the real object, but
internally it engages in messaging across the client to the server for all
method calls, dereferencing, etc.  It contains no actual data, and implements no
actual methods.

By the same token, when a client passes objects or other references to the
server as parameters to a method call, the server generates a proxy for those
objects, so that the remote method call may "call back" the client for detailed
access to the objects it passed.

The choice to proxy by default rather than generate a copy on the remote side by
default is distinct from some remoting systems.  It is, of course, possible to
explicitly ask the server to serialize a given object, but because a serialized
object may not behave the same way when it has lost its environment, this is not
the default behavior.

Proxied objects are only revealed as such by a call to ref(), which reveals the
object is actually an RMI::ProxyObject.  Calls to isa() and can() are proxied
across the connection to the remote side, and will maintain the correct API.
Remote objects which implement AUTOLOAD for their API will still work correctly.

Plain proxied references, and also proxied object, are also tied so as to
operate as the correct type of Perl primitive.  SCALAR, ARRAY, HASH, CODE and
GLOB/IO references, blessed or otherwise, will be proxied as the same type of
reference on the other side.  The RMI system uses Perl's "tie" functionality to
do this, and as a result proxied objects cannot be further tied on the
destination side.

=head1 GARBAGE COLLECTION

Until a proxy is destroyed, the side which sent the reference will keep an
additional reference to the real object, both to facilitate proxying, and to
prevent garbage collection.  Upon destruction on the reciever side, a message is
sent to the sender to expire its link to the item in question, and allow garbage
collection if no other references exist.

=head1 DEBUGGING RMI CODE

The environment variable RMI_DEBUG, has its value transferred to $RMI::DEBUG at
compile time.  When set to 1, this will cause the RMI modules to emit detailed
information to STDERR during all "conversations" between itself and the remote
side. This works for RMI::Client, RMI::Server, and anything else which inherits
from RMI::Node.

for example, using bash to run the first test case:

 RMI_DEBUG=1 perl -I lib t/01_*.t

The package variable $RMI::DEBUG_MSG_PREFIX will be printed at the beginning of
each message.  Changing this value allows the viewer to separate both halves of
a conversation.  The test suite sets this value to ' ' for the server side,
causing server activity to be indented.

=head1 SECURITY

=over 2

=head2 no inherent security is built-in

If you require restrctions on what the server provides, a custom sub-class
should be written around the server to restrict the types of calls it will receive.

This is wise whenever the server is exposed to an untrusted network.

=back

=head1 LIMITS TO TRANSPARENCY 

=over 2

=head2 calls to ref($my_proxy) reveal the true class RMI::ProxyObject

Proxied objects/references reveal that they are proxies when ref($o) is
called on them, unless the entire package is proxied with ->use_remote.

Calls to ->isa() still operate as though the proxy were the object it
represents.  Code which goes around the isa() override to UNIVERSAL::isa()
will circumvent the illusion as well.

=head2 use_remote() does not auto-proxy all package variables

Calls to "use_remote" will proxy subroutine calls, but not package variable
access automatically, besides @ISA.  If necessary, it must be done explicitly:

 $c->use_remote("Some::Package"); 
 # $Some::Package::foo is NOT bound to the remote variable of the same name

 *Some::Package::foo = $c->call_eval('\\$Some::Package::foo'); 
 # now it is...

=head2 the client may not be able to "tie" variables which are proxies

The RMI modules use "tie" on every proxy reference to channel access to the
other side.  The effect of attempting to tie a proxy reference may destroy its
ability to proxy.  (This is untested.)

In most cases, code does not tie a variable created elsewhere, because it
destroys its prior value, so this is unlikely to be an issue.

=head2 change to $_[$n] values will not affect the original variable

Remote calls to subroutines/methods which modify $_[$n] directly to tamper
with the caller's variables will not work as it would with a local method
call.

This is supportable, but adds considerable overhead to support modules which
create a side effect which is avoided because it is, mostly, a bad idea.

Perl technically passes an alias to even non-reference values, though the
common "my ($v1,$v2) = @_;" makes a copy which safely allows the subroutine to
behave as though the values were pass-by-copy.

 sub foo {
     $_[0]++; # BAD!
 } 
 my $v = 1; 
 foo($v); 
 $v == 2; # SURPRISE!

If foo() were called via RMI, in the current implementation, $v would still
have its original value.

Packages which implement this surprise behavior include Compress::Zlib!  If
this feature were added the overhead to Compress::Zlib would still make you
want to wrap the call...

=head2 anything which relies on caller() BESIDES EXPORT to will not work

This means that some modules which perform magic during import() may not work
as intended. 

=back

=head1 SEE ALSO

B<RMI::Server>, B<RMI::Client>, B<RMI::Node>, B<RMI::ProxyObject>, B<RMI::ProxyReference>

B<IO::Socket>, B<Tie::Handle>, B<Tie::Array>, B<Tie::Hash>, B<Tie::Scalar>

=head1 AUTHORS

Scott Smith <sakoht@cpan.org>

=head1 COPYRIGHT

Copyright (c) 2008 - 2009 Scott Smith <sakoht@cpan.org>  All rights reserved.

=head1 LICENSE

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

The full text of the license can be found in the LICENSE file included with this
module.

=cut

1;
