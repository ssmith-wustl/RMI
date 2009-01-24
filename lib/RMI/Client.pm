
package RMI::Client;

use strict;
use warnings;
use version;
our $VERSION = qv('0.1');

use base 'RMI::Node';

*call_sub = \&call_function;

sub call_function {
    my ($self,$fname,@params) = @_;
    return $self->send_request_and_receive_response(undef, $fname, @params);
}

sub call_class_method {
    my ($self,$class,$method,@params) = @_;
    $self->send_request_and_receive_response(undef, 'RMI::Node::_eval', "use $class");
    return $self->send_request_and_receive_response($class, $method, @params);
}

sub call_object_method {
    my ($self,$object,$method,@params) = @_;
    return $self->send_request_and_receive_response($object, $method, @params);
}

sub call_eval {
    my ($self,$src,@params) = @_;
    return $self->send_request_and_receive_response(undef, 'RMI::Node::_eval', $src, @params);
}

sub call_use {
    my $self = shift;
    for my $class (@_) {
        $self->send_request_and_receive_response(undef, 'RMI::Node::_eval', "use $class");
    }    
    return scalar(@_);    
}

sub call_use_lib {
    my $self = shift;
    for my $class (@_) {
        $self->send_request_and_receive_response(undef, 'RMI::Node::_eval', "use lib '$class'");
    }    
    return scalar(@_);    
}

sub use_remote {
    my $self = shift;
    my $class = shift;
    $self->_bind_local_class_to_remote($class, undef, @_);
    $self->_bind_local_var_to_remote('@' . $class . '::ISA');
    return 1;
}

sub use_lib_remote {
    my $self = shift;
    unshift @INC, $self->virtual_lib;
}

sub bind {
    my $self = shift;
    if (substr($_[0],0,1) =~ /\w/) {
        $self->_bind_local_class_to_remote(@_);
    }
    else {
        $self->_bind_local_var_to_remote(@_);
    }
}

=pod

=head1 NAME

RMI::Client - a connection for requesting remote objects and processing 

=head1 SYNOPSIS


 $c = RMI::Client::Tcp->new(host => 'server1', port => 1234);
 $c = RMI::Client::ForkedPipes->new();
 $c = RMI::Client->new(reader => $fh1, writer => $fh2); # generic
 
 $c->call_use('IO::File');
 $c->call_use('Sys::Hostname');

 $o = $c->call_class_method('IO::File','new','/tmp/myfile');
 print $o->getline;
 print <$o>;

 $host = $c->call_function('Sys::Hostname::hostname')
 $host eq 'server1'; #!
 
 $h1 = $c->call_eval('$main::h = { k1 => 111, k2 => 222, k3 => 333}'); 
 $h1->{k4} = 444;
 print sort keys %$h1;
 print $c->call_eval('sort keys %$main::h');

 $c->use_remote('Sys::Hostname');
 $host = Sys::Hostname::hostname(); # lie!

 BEGIN {$c->use_lib_remote;}
 use Some::Class; # remote!
 
 # see the docs for B<RMI> for more examples...
 
=head1 DESCRIPTION

This is the base class for a standard RMI connection to an RMI::Server.

In most cases, you will create a client of some subclass, typically
RMI::Client::Tcp for a network socket, or RMI::Client::ForkedPipes
for an out-of-process object server.

=head1 METHODS

=over 4
 
=item call_class_method($class, $method, @params)

Does $class->$method(@params) on the remote side.

Calling remote constructors is the primary way to make a remote object.

 $remote_obj = $client->call_class_method('Some::Class','new',@params);
 
 $possibly_another_remote_obj = $remote_obj->some_method(@p);
 
=item call_function($fname, @params)

A plain function call made by name to the remote side.  The function name must be fully qualified.

 $c->call_use('Sys::Hostname');
 my $server_hostname = $c->call_function('Sys::Hostname::hostname');

=item call_sub($fname, @params)

An alias for call_function();

=item call_eval($src,@args)

Calls eval $src on the remote side.

Any additional arguments are set to @_ before eval on the remote side, after proxying.

    my $a = $c->call_eval('@main::x = (11,22,33); return \@main::x;');  # pass an arrayref back
    push @$a, 44, 55;                                                   # changed on the server
    scalar(@$a) == $c->call_eval('scalar(@main::x)');                   # ...true!

=item call_use($class)

Uses the Perl package specified on the remote side, making it available for later
calls to call_class_method() and call_function().

 $c->call_use('Some::Package');
 
=item call_use_lib($path);

Calls "use lib '$path'" on the remote side.

 $c->call_use_lib('/some/path/on/the/server');
 
=item use_remote($class)

Creases the effect of "use $class", but all calls of any kind for that
namespace are proxied through the client.  This is the most transparent way to
get remote objects, since you can just call normal constructors and class methods
as though the module were local.  It does means that ALL objects of the given
class must come from through this client.

 # NOTE: you probably shouldn't do this with IO::File unless you
 # _really_ want all of its files to open on the server,
 # while open() opens on the client...
 
 $c->use_remote('IO::File');    # never touches IO/File.pm on the client                                
 $fh = IO::File->new('myfile'); # actually a remote call
 print <$fh>;                   # printing rows from a remote file

 require IO::File;              # does nothing, since we've already "used" IO::File
 
The @ISA array is also bound to the remote @ISA, but all other variables
must be explicitly bound on the client to be accessible.  This may be changed in a
future release.

Also note that "export" does not currently work via the RMI client.  This
may also change in a future release.

=item use_lib_remote($path)

Installs a special handler into the local @INC which causes it to check the remote
side for a class.  If available, it will do use_remote() on that class.

 use A;
 use B; 
 BEGIN { $c->use_remote_lib; }; # do everything remotely from now on if possible...
 use C; #remote!
 use D; #remote!
 use E; #local, b/c not found on the remote side

=back

=head1 EXAMPLES

=over
    
=item Making a remote hashref

This makes a hashref on the server, and makes a proxy on the client:
    my $fake_hashref = $c->call_eval('{}');

This seems to put a key in the hash, but actually sends a message to the server to modify the hash.
    $fake_hashref->{key1} = 100;

Lookups also result in a request to the server:
    print $fake_hashref->{key1};

When we do this, the hashref on the server is destroyed, as since the ref-count on both sides is now zero:
    $fake_hashref = undef;

=item Making a remote CODE ref, and using it with a mix of local and remote objects

    my $local_fh = IO::File->new('/etc/passwd');
    my $remote_fh = $c->call_class_method('IO::File','new','/etc/passwd');
    my $remote_coderef = $c->call_eval('
                            sub {
                                my $f1 = shift; my $f2 = shift;
                                my @lines = (<$f1>, <$f2>);
                                return scalar(@lines)
                            }
                        ');
    my $total_line_count = $remote_coderef->($local_fh, $remote_fh);

=back

=head1 BUGS AND CAVEATS

See general bugs in B<RMI> for general system limitations

=head1 SEE ALSO

B<RMI::Server> B<RMI::Client>

B<IO::Socket>, B<Tie::Handle>, B<Tie::Array>, B<Tie:Hash>, B<Tie::Scalar>

=cut

1;

