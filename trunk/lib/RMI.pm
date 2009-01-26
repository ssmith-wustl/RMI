package RMI;

use strict;
use warnings;
use version;
our $VERSION = qv('0.02');

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

    my $s = RMI::Server::Tcp->new(port => 1234); $s->run;


#process 2: an example client

    my $c = RMI::Client::Tcp->new(
       host => 'myserver', port => 1234,
    );

    $c->call_use('IO::File'); $o =
    $c->call_class_method('IO::File','new','/etc/passwd');

    $line1 = $o->getline;           # works as an object

    $line2 = <$o>;                  # works as a file handle
    @rest  = <$o>;                  # detects scalar/list context correctly

    $o->isa('IO::File');            # transparent in standard ways
    $o->can('getline');
    
    ref($o) eq 'RMI::ProxyObject';  # the only sign this isn't a real IO::File...
				    # (see use_remote() to fix this)

=head1 DESCRIPTION

The RMI suite includes RMI::Client and RMI::Server classes to support
transparent object proxying.  An RMI::Client allows an application to invoke
code in the related RMI::Server's process.  Returned data from the server is
presented virtually to the client via a "proxy" object/reference.  The proxy
object behaves as though it were the real item in question, but redirects all
interaction to the real object in the other process.

The proxying or objects via a remote stub goes by the term "RMI" in Java, "Drb"
in Ruby, "PYRO" in Python, "Remoting" in .NET, and is similar in functionality
to architectures such as CORBA, and the older DCOM.

None of the above use the same protocols (except Java's RMI has an optional
CORBA implementation), and this module is no exception, sadly.  Patches are
welcome.

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

=head1 TYPES OF CLIENTS AND SERVERS

All RMI client and server objects use a pair of handles for messaging.  Specific
subclasses of RMI::Client and RMI::Server implement the handles in different
ways.  There are two implementations which are part of the default RMI package:

=over 4

=item RMI::Client::Tcp and RMI::Server::Tcp

A TCP/IP socket server for cross-network proxies.  The current implementation
supports multiple clients, and is a single-threaded non-blocking server.

=item RMI::Client::ForkedPipes and RMI::Server::ForkedPipes

Creates its own private server in a sub-process.  Useful if you want an
out-of-process object b/c you plan to exceed Perl's memory limit on a 32-bit
machine, or for testing w/o making a socket.

(This is also used by custom server apps since the server will exec() whatever
was passed to the client constructor after fork().  In particular, it was built
to allow cross-langage RMI.)

=back

=head1 METHODS

The RMI module has no public methods of its own.  See <RMI::Client> and
<RMI::Server> for APIs for interaction.

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

=head1 FUNCTIONALITY CAVEATS

=over 2

=item Proxied objects/references reveal that they are proxies when ref($o) is
called on them, unless the entire package is proxied with ->use_remote.

  There is no way to override ref(), as far as I know.

=item No inherent security is built-in.

  Writing a wrapper for an RMI::Server which limits the calls it supports, and
  the data returnable would be easy, but it has not been done.  Specifically,
  turning off call_eval() is wise in untrusted environments.

=item use_remote() does not proxy all package variables automatically

  Calls to "use_remote" will proxy subroutine calls, but not package variable
  access automatically.

  Also implementable, but this does not happen automatically except for @ISA in
  the current implementation.

  $c->use_remote("Some::Package"); # $Some::Package::foo is NOT bound to the
  remote variable of the same name

  *Some::Package::foo = $c->call_eval('\\$Some::Package::foo'); # now it is...

=back

=head1 BUGS

=over 2

=item The client may not be able to "tie" variables which are proxies.

  The RMI modules use "tie" on every proxy reference to channel access to the
  other side.  The effect of attempting to tie a proxy reference may destroy its
  ability to proxy.  (This is untested.)

  In most cases, code does not tie a variable created elsewhere, because it
  destroys its prior value, so this is unlikely to be an issue.

=item Direct change to $_[$n] values will fail to affect the original variable

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
  } my $v = 1; foo($v); $v == 2; # SURPRISE!

  If foo() were called via RMI, in the current implementation, $v would still
  have its original value.

  Packages which implement this surprise behavior include Compress::Zlib!  If
  this feature were added the overhead to Compress::Zlib would still make you
  want to wrap the call...

=item Anything which relies on caller() to check the call stack will not work.

  This means that some modules which perform magic during import() may not work
  as intended.  Exporting DOES work even so far as to require that the
  application do this:
    
    $c->use_remote('Sys::Hostname',[]);
    
  To get this effect (and prevent export of the hostame() function).
  
    use Sys::Hostname ();

=item The serialization mechanism needs to be made more robust and efficient.

 It's really just enough to "work".

 The current implementation uses Data::Dumper with options which should remove
 newlines.  Since we do not flatten arbitrary data structures, a simpler parser
 would be more efficient.

 The message type is currently a text string.  This could be made smaller.

 The data type before each paramter or return value is an integer, which could
 also be abbreviated futher, or we could go the other way and be more clear. :)

 This should switch to sysread and pass the message length instead of relying on
 buffers, since the non-blocking IO might not have issues.

=back

=head1 SEE ALSO

B<RMI::Server>, B<RMI::Client>, B<RMI::Node>, B<RMI::ProxyObject>,
B<RMI::ProxyReference>

B<IO::Socket>, B<Tie::Handle>, B<Tie::Array>, B<Tie:Hash>, B<Tie::Scalar>

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
