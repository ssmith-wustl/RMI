
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
our $DEBUG_INDENT = '';

# flag checked by DESTROY handlers
our $process_is_ending = 0;
sub END {
    $process_is_ending = 1;
}

=pod

=head1 NAME

RMI - mostly transparet Remote Method Invocation

=head1 SYNOPSIS

process 1: the server on host "foo"

 $s = RMI::Server::Tcp->new(
    port => 1234,
    allow_eval => 1,
    allow_packages => ['IO::File','Sys::Hostname', qr/Bio::.*/];
 );
 $s->run;
 
process 2: the client on another host

 $c = RMI::Client::Tcp->new(
    host => "foo",
    port => 1234,
 );

 # do the whole class remotely...
 $c->use_remote("IO::FILE");
 $o = IO::File->new("/etc/passwd");
 print $o->getlines;

 # or do individual remote operations...
 $o = $c->call_class_method("IO::File","new","/etc/passwd");
 $server_hostname = $c->call_function("Sys::Hostname::hostname");
 $otherpid = $c->remote_eval('$$'); 
 
 # changes to perl refs are visible from both sides 
 $a = $c->remote_eval('@main::x = [11,22,33]; return \@x;');
 push @$a, 44, 55;
 $n1 = $c->remote_eval('scalar(@main::x));
 # 5!

 # references from either side can be used on either side
 $local_fh = IO::File->new("/etc/passwd");
 $remote_fh = $c->call_class_method('IO::File','new',"/etc/passwd");
 $remote_coderef = $c->remote_eval("sub { my $f1 = shift; my $f2 = shift; @lines = ($f1->getlines, $f2->getlines); return scalar(@lines) }");
 $total_line_count = $remote_coderef->($local_fh, $remote_fh);

 # very transparent...
 $o->isa('IO::File');
 $o->can("getline");

 # ...but not completely (this works if you bring in the whole class with use_remote)
 ref($o); # RMI::ObjectProxy
  
 
=head1 DESCRIPTION

The RMI allow individual objects, individual data structures, and entire classes to exist in a remote process,
but be used transparently in the local process via proxy.

This goes by the term RMI in Java, "Remoting" in .NET, and is similar in functionalty to architectures such as CORBA.

Note: this implementation uses proxies for all references.  Objects are never serialized.

=cut

=head1 METHODS

The RMI module has no public methods of its own.  See <RMI::Client> and <RMI::Server> for APIs for interaction.

=back

=head1 BUGS

=over 2

=item Individually proxied objects reveal that they are proxies when ref($o) is called on them.

 There is no way to override this, as far as I know.

=item When unblessed references are passed, they are "tied" on the originating side.

This will break if the reference is already tied.  The fix is to detect that it is tied, and retain the package name.
That package name must be used when proxying back.
This probably also introduces overhead, which could be handled by custom code instead.
 
=item Handles are not transferred correctly.

Methods wil work, but <$fh> will not.

=item The serialization mechanism needs to be made more robust.

The current implementation uses Data::Dumper, and removes newlines.  This must escape them to work robustly.
Ideally, the text sent is the same text you could use in sprintf.  Storable/FreezeThaw are also options,
but they will not work cross-language.

=back

Report bugs to <software@genome.wustl.edu>.

=head1 SEE ALSO

B<IO::Socket>

=head1 AUTHOR

Scott Smith <ssmith@genome.wustl.edu>
Anthony Brummett <abrummet@genome.wustl.edu>

=cut


1;

