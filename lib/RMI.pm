
package RMI;

use strict;
use warnings;

# the whole family
use RMI::Node;
use RMI::Client;
use RMI::Server;
use RMI::ProxyObject;
use RMI::ProxyReference;
use Data::Dumper;

# turn on debug messages
our $DEBUG;
BEGIN { $RMI::DEBUG = $ENV{RMI_DEBUG}; };

# control debug messages
our $DEBUG_MSG_PREFIX = '';

# flag checked by DESTROY handlers
our $process_is_ending = 0;
sub END {
    $process_is_ending = 1;
}

=pod

=head1 NAME

RMI - mostly transparet Remote Method Invocation

=head1 SYNOPSIS


#process 1: an example server on host "myserver"

    my $s = RMI::Server::Tcp->new(port => 1234);
    $s->run;


#process 2: an example client

    my $c = RMI::Client::Tcp->new(
       host => 'myserver',
       port => 1234,
    );

    $o = $c->call_class_method("IO::File","new","/etc/passwd");
    $o->isa("IO::File");
    $o->can("getline");
    ref($o) eq'RMI::ProxyObject'; #! :(
    
    $line1 = $o->getline;
    $line2 = <$o>;
    @rest  = <$o>;

    my $a = $c->remote_eval('@main::x = (11,22,33); return \@main::x;');
    push @$a, 44, 55;
    
    scalar(@$a) == $c->remote_eval('scalar(@main::x)')
    #!!!
    
    $c->use_remote("use Sys::Hostname");
    my $server_hostname = $c->call_function("Sys::Hostname::hostname");
    
    my $otherpid = $c->remote_eval('$$'); 
        
    my $a = $c->remote_eval('@x = (11,22,33); return \@main::x;');
    push @$a, 44, 55;
    scalar(@$a) == $c->remote_eval('scalar(@main::x)'); # true!
    
    my $local_fh = IO::File->new("/etc/passwd');
    my $remote_fh = $c->call_class_method('IO::File','new',"/etc/passwd");
    my $remote_coderef = $c->remote_eval('sub { my $f1 = shift; my $f2 = shift; my @lines = (<$f1>, <$f2>); return scalar(@lines) }');
    my $total_line_count = $remote_coderef->($local_fh, $remote_fh);
      
    $c->use_remote("IO::File");
    # ...
    $o = IO::File->new("/etc/passwd");
    ref($o) == 'RMI::ProxyObject';
        
    use A; 
    use B; 
    BEGIN { $c->use_remote_lib; }; # do everything remotely from now on if possible...
    use C; #remote!
    use D; #remote!
    use E; #local, b/c not found on the remote side
    
=head1 DESCRIPTION

The RMI suite includes RMI::Client and RMI::Server classes.  An RMI::Client module allows an application to call code
in a remote process which is running an RMI::Server.  Parameters and results are passed as transparent proxy
objects/references.  There is no "serialization".  

This goes by the term "RMI" in Java, "Remoting" in .NET, and is similar in functionalty to architectures such as CORBA,
and the older DCOM.

=head1 PROXY OBJECTS AND REFERENCES

Parameters and return values which are non-reference values are passed to the other side by copy.  When a parameter is
a reference, the sender keeps a link to the object in question for the receiver, and sends the receiver an ID for the item.
The receiver produces a proxy reference, which calls back to the sender for all attempts to interact with it.  Upon
destruction on the reciever side, a message is sent to the sender to expire its link to the item in question.

This means that, if the remote call returns an object which is a blessed Hash reference, the client will receive a "proxy"
reference which has been tied and blessed, and attempts to appear to be the blessed Hashref it represents.  All attempts to interact
with the reference will be passed-back to the server for resolution.

The RMI module works correctly with GLOBs, CODE references, blessed and unblessed references, and tied references.

=cut


=head1 METHODS

The RMI module has no public methods of its own.  See <RMI::Client> and <RMI::Server> for APIs for interaction.

=back



The environment variable RMI_DEBUG, has its value transferred to $RMI::DEBUG
at compile time.  When set to 1, this will cause the RMI modules to emit detailed
information to STDERR during its conversation.

for example, using bash to run the first test case:
RMI_DEBUG=1 perl -I lib t/01_*.t

The package variable $RMI::DEBUG_MSG_PREFIX will be printed at the beginning of each message.
Changing this value allows the viewer to separate both halves of a conversation.
The test suite sets this value to ' ' for the server side, causing server activity
to be indented.

=head1 BUGS

=over 2

=item Proxied objects/references reveal that they are proxies when ref($o) is called on them.

  There is no way to override this, as far as I know.

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

=item The client may not be able to "tie" variables which are proxies.

  The RMI modules use "tie" on every proxy reference to channel access to the other side.
  The effect of attempting to tie a proxy reference may destroy its ability to proxy.
  (This is untested.)
  
  In most cases, code does not tie a variable created elsewhere, because it destroys its prior value,
  so this is unlikely to be an issue.

=item The serialization mechanism needs to be made more robust and efficient.

 The current implementation uses Data::Dumper with options which should remove newlines.
 Since we do not flatten arbitrary data structures, a simpler parser would be more efficient.

 The message type is currently a text string.  This could be made smaller.

 The data type before each paramter or return value is an integer, which could also
 be abbreviated futher, or we could go the other way and be more clear. :)

 We should switch to sysread and pass the message length instead of relying on buffers,
 since the non-blocking IO might not have issues.

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

Report bugs to <software@genome.wustl.edu>.

=head1 SEE ALSO

B<IO::Socket>, B<Tie::StdHandle>, B<Tie::Array>, B<Tie:Hash>, B<Tie::Scalar>

=head1 AUTHOR

Scott Smith <ssmith@genome.wustl.edu>
Anthony Brummett <abrummet@genome.wustl.edu>

=cut


1;

