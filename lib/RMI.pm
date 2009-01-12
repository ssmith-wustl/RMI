
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


#process 1: the server

    use RMI::Server;
    my $s = RMI::Server::Tcp->new(
        port => 1234,
        allow_eval => 1,
        allow_packages => ['IO::File','Sys::Hostname', qr/Bio::.*/],
    );
    $s->run;


#process 2: the client on another host

    my $c = RMI::Client::Tcp->new(
       host => 'myserverhost',
       port => 1234,
    ); 
    
    my $server_hostname = $c->call_function("Sys::Hostname::hostname");
    
    my $otherpid = $c->remote_eval('$$'); 
    
    my $o = $c->call_class_method("IO::File","new","/etc/passwd");
    $o->isa("IO::File");
    $o->can("getline");
    ref($o) == 'RMI::ProxyObject'; #!
    @lines = $o->getlines;

    my $a = $c->remote_eval('@main::x = (11,22,33); return \@main::x;');
    push @$a, 44, 55;
    
    scalar(@$a) == $c->remote_eval('scalar(@main::x)')
    #!!!
    
    my $local_fh;
    open($local_fh, "/etc/passwd");
    my $remote_fh = $c->call_class_method('IO::File','new',"/etc/passwd");
    my $remote_coderef = $c->remote_eval('sub { my $f1 = shift; my $f2 = shift; my @lines = ($f1->getlines, $f2->getlines); return scalar(@lines) }');
    my $total_line_count = $remote_coderef->($local_fh, $remote_fh);
    
    # do a whole class remotely
    
    $c->use_remote("IO::File");
    $o = IO::File->new("/etc/passwd");
    my @lines = $o->getlines;
    ok(scalar(@lines) > 1, "got " . scalar(@lines) . " lines");
    
    # make remoting default
    use A;
    use B;
    BEGIN { $c->use_remote_lib; }; # do everything remotely from now on...
    use C; #remote!
    use D; #remote!
    
=head1 DESCRIPTION

The RMI allow individual objects, individual data structures, and entire classes to exist in a remote process,
but be used transparently in the local process via proxy.

This goes by the term RMI in Java, "Remoting" in .NET, and is similar in functionalty to architectures such as CORBA.

Note: this implementation uses proxies for all references.  Objects are never serialized.

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

=item Individually proxied objects reveal that they are proxies when ref($o) is called on them.

 There is no way to override this, as far as I know.

=item The serialization mechanism needs to be made more robust and efficient.

 The current implementation uses Data::Dumper with options which should remove newlines.
 Since we do not flatten arbitrary data structures, a simpler parser would be more efficient.

 The message type is currently a text string.  This could be made smaller.

 The data type before each paramter or return value is an integer, which could also
 be abbreviated futher, or we could go the other way and be more clear. :)

 We should switch to sysread and pass the message length instead of relying on buffers,
 since the non-blocking IO might not have issues.

=back

Report bugs to <software@genome.wustl.edu>.

=head1 SEE ALSO

B<IO::Socket>, B<Tie::StdHandle>, B<Tie::Array>, B<Tie:Hash>, B<Tie::Scalar>

=head1 AUTHOR

Scott Smith <ssmith@genome.wustl.edu>
Anthony Brummett <abrummet@genome.wustl.edu>

=cut


1;

