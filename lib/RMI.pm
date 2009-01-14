package RMI;

use strict;
use warnings;
use version;
our $VERSION = qv('0.1');

# the whole base set of classes which make general RMI work
# (sub-classes of RMI Server & Client provide specific implementations such as sockets, etc.)
use RMI::Node;
use RMI::Client;
use RMI::Server;
use RMI::ProxyObject;
use RMI::ProxyReference;

# turn on debug messages if an environment variable is set
our $DEBUG;
BEGIN { $RMI::DEBUG = $ENV{RMI_DEBUG}; };

# this is used at the beginning of each debug message
# setting it to a single space for a server makes server/client distinction
# more readable in combined output.
our $DEBUG_MSG_PREFIX = '';

=pod

=head1 NAME

RMI - (mostly) transparet Remote Method Invocation

=head1 SYNOPSIS


#process 1: an example server on host "myserver"

    my $s = RMI::Server::Tcp->new(port => 1234);
    $s->run;


#process 2: an example client

    my $c = RMI::Client::Tcp->new(
       host => 'myserver',
       port => 1234,
    );

    $c->remote_use('Sys::Hostname');
    my $server_hostname = $c->call_function('Sys::Hostname::hostname');

    $c->remote_use('IO::File');
    $o = $c->call_class_method('IO::File','new','/etc/passwd');
        
    $line1 = $o->getline;  # works as an object
    $line2 = <$o>;         # works as a file handle
    @rest  = <$o>;         # detects scalar/list context correctly
    
    $o->isa('IO::File');                        # transparent!
    $o->can('getline');                         # transparent!
    ref($o) eq 'RMI::ProxyObject';              # the only sign this isn't a real IO::File...

    my $server_pid = $c->remote_eval('$$');     # execute arbitrary code to get $$ (the process id)
    
    my $a = $c->remote_eval('@x = (11,22,33); return \@main::x;');  # pass an arrayref back
    push @$a, 44, 55;                                               # changed on the server
    scalar(@$a) == $c->remote_eval('scalar(@main::x)');             # ...true
    
    $c->use_remote('IO::File');         # like remote_use, but makes ALL IO::File activity remote
    require IO::File;                   # does nothing, since we've already "used" IO::File
    $o = IO::File->new('/etc/passwd');  # makes a remote call...
    ref($o) == 'IO::File';              # object seems local!
    
    use A;
    use B; 
    BEGIN { $c->use_remote_lib; }; # do everything remotely from now on if possible...
    use C; #remote!
    use D; #remote!
    use E; #local, b/c not found on the remote side
    
=head1 DESCRIPTION

The RMI suite includes RMI::Client and RMI::Server classes.  An RMI::Client module allows an application to generate 
objects in a remote process which is running an RMI::Server, and use them via a "proxy".  The proxy object behaves
as though it were the real object/reference, but redirects all interaction to the real object server.

The proxying or objects via a remote stub goes by the term "RMI" in Java, "Remoting" in .NET, and is similar in functionalty
to architectures such as CORBA, and the older DCOM.

=head1 PROXY OBJECTS AND REFERENCES

Parameters and results for remote method calls (and also plain subroutine calls, and remote_eval() calls) are passed
as transparent proxies when they are references of any sort.  This includes objects, and also HASH refrences, ARRAY
references, SCALAR references, GLOBs/IO-handles, and CODE references, including closures.  Proxy objects are also
usable as their primitive Perl type, in addition to dispatching method calls.  

As such there is NO "SERIALIZATION" of data structures.  When a method returns a hashref, the client gets something
which looks and acts like a hashref, but access to it results in activity across the client-server connection.

Objects and references keep state in the process in which they originate.  Only parameters and return values which
are non-reference values are passed to the other side by copy.

When a parameter is a reference, the sender keeps a link to the object in question for the receiver, and sends
the receiver an ID for the item.  The receiver produces a proxy reference, which calls back to the sender for
all attempts to interact with it.  Upon destruction on the reciever side, a message is sent to the sender to expire
its link to the item in question, and allow garbage collection if no other references exist.

=head1 TYPES OF CLIENTS AND SERVERS

All RMI client and server objects use a pair of handles for messaging.  Specific subclasses of RMI::Client
and RMI::Server implement the handles in different ways.

See:

=over 4

=item RMI::Client::Tcp and RMI::Server::Tcp

A single-threaded non-blocking TCP/IP socket server for cross-internet proxying.

=item RMI::Client::ForkedPipes

Creates its own private server in a sub-process.  Useful if you want an out-of-process object b/c you
plan to exceed Perl's memory limit on a 32-bit machine, or need to exec() to run a server using another language.

=back


=head1 METHODS

The RMI module has no public methods of its own.  See <RMI::Client> and <RMI::Server> for APIs for interaction.

The environment variable RMI_DEBUG, has its value transferred to $RMI::DEBUG
at compile time.  When set to 1, this will cause the RMI modules to emit detailed
information to STDERR during its conversation.

for example, using bash to run the first test case:
RMI_DEBUG=1 perl -I lib t/01_*.t

The package variable $RMI::DEBUG_MSG_PREFIX will be printed at the beginning of each message.
Changing this value allows the viewer to separate both halves of a conversation.
The test suite sets this value to ' ' for the server side, causing server activity
to be indented.

=head1 EXAMPLES

These are esoteric examples which push the boundaries of the system:

=item MAKING A REMOTE HASHREF

This makes a hashref on the server, and makes a proxy on the client:
    my $fake_hashref = $c->remote_eval('{}');

This seems to put a key in the hash, but actually sends a message to the server to modify the hash.
    $fake_hashref->{key1} = 100;

Lookups also result in a request to the server:
    print $fake_hashref->{key1};

When we do this, the hashref on the server is destroyed, as since the ref-count on both sides is now zero:
    $fake_hashref = undef;

=item MAKING A REMOTE SUBROUTINE REFERENCE, AND USING IT WITH A MIX OF LOCAL AND REMOTE OBJECTS

    my $local_fh = IO::File->new('/etc/passwd');
    my $remote_fh = $c->call_class_method('IO::File','new','/etc/passwd');
    my $remote_coderef = $c->remote_eval('
                            sub {
                                my $f1 = shift; my $f2 = shift;
                                my @lines = (<$f1>, <$f2>);
                                return scalar(@lines)
                            }
                        ');
    my $total_line_count = $remote_coderef->($local_fh, $remote_fh);
    
=item

=head1 CAVEATS

=over 2

=item Anything which relies on caller() to check the call stack may not work as intended.

  This means that some modules which perform magic during import() may not work as intended.

=item Proxied objects/references reveal that they are proxies when ref($o) is called on them, unless the entire package is proxied with ->use_remote.

  There is no way to override this, as far as I know.

=item No inherent security is built-in.

 Writing a wrapper for an RMI::Server which limits the calls it supports, and the data
 returnable would be easy, but it has not been done.  Specifically, turning off
 remote_eval() is wise in untrusted environments.

=item Calls to "use_remote" will proxy subroutine calls, but not package variable access automatically.


  Also implementable, but this does not happen automatically.  Perhaps it should for @ISA?
  
  $c->use_remote("Some::Package");
  # $Some::Package::foo is NOT bound to the remote variable of the same name
  
  *Some::Package::foo = $c->remote_eval('\\$Some::Package::foo');
  # now it is...

=back

=head1 BUGS

=over 2

=item The client may not be able to "tie" variables which are proxies.

  The RMI modules use "tie" on every proxy reference to channel access to the other side.
  The effect of attempting to tie a proxy reference may destroy its ability to proxy.
  (This is untested.)
  
  In most cases, code does not tie a variable created elsewhere, because it destroys its prior value,
  so this is unlikely to be an issue.

=item Remote calls to subroutines/methods which modify $_[$n] directly to tamper with the caller's variables will fail.

  This is supportable, but adds considerable overhead to support modules which create a
  side effect which is avoided because it is, mostly, a bad idea.

  Perl technically passes an alias to even non-reference values, though the common "my ($v1,$v2) = @_;"
  makes a copy which safely allows the subroutine to behave as though the values were pass-by-copy.
  
  sub foo {
    $_[0]++; # BAD!
  }
  my $v = 1;
  foo($v);
  $v == 2; # SURPRISE!

  If foo() were called via RMI, in the current implementation, $v would still have its original value.
  
  Packages which implement this surprise behavior include Compress::Zlib!  If this feature were added
  the overhead to Compress::Zlib would still make you want to wrap the call...

=item The serialization mechanism needs to be made more robust and efficient.

 It's really just enough to "work".

 The current implementation uses Data::Dumper with options which should remove newlines.
 Since we do not flatten arbitrary data structures, a simpler parser would be more efficient.

 The message type is currently a text string.  This could be made smaller.

 The data type before each paramter or return value is an integer, which could also
 be abbreviated futher, or we could go the other way and be more clear. :)

 We should switch to sysread and pass the message length instead of relying on buffers,
 since the non-blocking IO might not have issues.

=back

=head1 SEE ALSO

B<RMI::Server> B<RMI::Client>, B<RMI::Node>

B<IO::Socket>, B<Tie::Handle>, B<Tie::Array>, B<Tie:Hash>, B<Tie::Scalar>

=head1 AUTHOR

Scott Smith <sakoht@cpan.org>                    

=cut

1;

