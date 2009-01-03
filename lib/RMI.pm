
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

RMI - Remote Method Invocation

=head1 SYNOPSIS

 # process 1: the server on host "foo"
 $s = RMI::Server::Tcp->new(
    port => 1234,
    allow_eval => 1,
    allow_packages => ['IO::File','Sys::Hostname', qr/Bio::.*/];
 );
 $s->run;
 
 # process 2: the client on another host
 $c = RMI::Client::Tcp->new(
    host => "foo",
    port => 1234,
 );

 # get an object: this is a transparent proxy, NOT serialized
 $o = $c->call_class_method("IO::File","new","/etc/passwd");

 # all method calls run on the server...
 print scalar($o->getlines)," lines in the remote file\n";
 
 # basic function calls work too
 $server_hostname = $c->call_function("Sys::Hostname::hostname");
 
 # as does direct eval()
 $otherpid = $c->remote_eval('$$'); # nnnn
 
 # changes to data structures appear on both sides
 $a = $c->remote_eval('@main::x = [11,22,33]; return \@x;');
 print ref($a); # ARRAY
 push @$a, 44, 55;
 $c->remote_eval('push @main::x, 66, 77');
 $n1 = $c->remote_eval('scalar(@main::x));
 # 7!
 $n2 = scalar(@$a);
 # 7!

 # you can pass local objects across, and pass-back remote objects
 $local_fh = IO::File->new("/etc/passwd");
 $remote_fh = $c->call_class_method('IO::File','new',"/etc/passwd");
 $remote_coderef = $c->remote_eval("sub { my $f1 = shift; my $f2 = shift; @lines = ($f1->getlines, $f2->getlines); return scalar(@lines) }");
 $total_line_count = $remote_coderef->($local_fh, $remote_fh);

 # objects look and works the same
 $o->isa('IO::File');
 $o->can("getline");   # a CODE ref which, if called, goes to the other side

 # EXCEPT HERE
 print ref($o); # RMI::ProxyObject

 # UNLESS YOU BRING IN THE ENTIRE CLASS
 $c->use_remote("IO::FILE");
 $o = IO::File->new("/etc/passwd");
 ref($o); # IO::File, but the object is still remote
 
=head1 DESCRIPTION

The RMI allow individual objects, individual data structures, and entire classes to exist in a remote process,
but be used transparently in the local process via proxy.

This goes by the term RMI in Java, "Remoting" in .NET, and is similar in functionalty to architectures such as CORBA.

=cut

=head1 METHODS

These methods provide the basic functionality common to (nearly) all
applications.

=over 4

=item init

  App->init

This methods perfoms all initialization tasks.  Certain tasks will be
set up by the packages that App uses.  You can set your own using
App::Init::add_init_subroutine (see
L<App::Init/"add_init_subroutine">).

 
=item authorization_handler 
 
    App->authorization_handler(\&mysub); 
 
Specify the subroutine which should authorize potentially restricted 
actions in the application.  The subroutine should accept the same 
parameters as are passed to App->authorize below. 


=back

=head1 BUGS

Report bugs to <software@genome.wustl.edu>.

=head1 SEE ALSO

IO::Socket

=head1 AUTHOR

Scott Smith <ssmith@genome.wustl.edu>

=cut


1;

