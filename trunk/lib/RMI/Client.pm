
package RMI::Client;

use strict;
use warnings;
use version;
our $VERSION = qv('0.1');

use base 'RMI::Node';

#
# PUBLIC API
#

*call_sub = \&call_function;

sub call_function {
    my ($self,$fname,@params) = @_;
    return $self->send_request_and_receive_response('call_function', undef, $fname, \@params);
}

sub call_class_method {
    my ($self,$class,$method,@params) = @_;
    return $self->send_request_and_receive_response('call_class_method', $class, $method, \@params);
}

sub call_object_method {
    my ($self,$object,$method,@params) = @_;
    return $self->send_request_and_receive_response('call_object_method', $object, $method, \@params);
}

sub call_eval {
    my ($self,$src,@params) = @_;
    return $self->send_request_and_receive_response('call_eval', undef, 'RMI::Server::_receive_eval', [$src, @params]);    
}

sub call_use {
    my $self = shift;
    my $class = shift;
    my $module = shift;
    my $use_args = shift;

    my @exported;
    my $path;
    
    ($class,$module,$path, @exported) = 
        $self->send_request_and_receive_response(
            'call_use',
            undef,
            'RMI::Server::_receive_use',
            [
                $class,
                $module,
                defined($use_args),
                ($use_args ? @$use_args : ())
            ]
        );
        
    return ($class,$module,$path,@exported);
}

sub call_use_lib {
    my $self = shift;
    my $lib = shift;
    return $self->send_request_and_receive_response('call_use_lib', undef, 'RMI::Server::_receive_use_lib', [$lib]);
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

sub virtual_lib {
    my $self = shift;
    my $virtual_lib = sub {
        $DB::single = 1;
        my $module = pop;
        $self->_bind_local_class_to_remote(undef,$module);
        my $sym = Symbol::gensym();
        my $done = 0;
        return $sym, sub {
            if (! $done) {
                $_ = '1;';
                $done++;
                return 1;
            }
            else {
                return 0;
            }
        };
    }
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


#
# PRIVATE API
#

# this proxies a single variable

sub _bind_local_var_to_remote {
    my $self = shift;
    my $local_var = shift;
    my $remote_var = (@_ ? shift : $local_var);
    
    my $type = substr($local_var,0,1);
    if (index($local_var,'::')) {
        $local_var = substr($local_var,1);
    }
    else {
        my $caller = caller();
        $local_var = $caller . '::' . substr($local_var,1);
    }

    unless ($type eq substr($remote_var,0,1)) {
        die "type mismatch: local var $local_var has type $type, while remote is $remote_var!";
    }
    if (index($remote_var,'::')) {
        $remote_var = substr($remote_var,1);
    }
    else {
        my $caller = caller();
        $remote_var = $caller . '::' . substr($remote_var,1);
    }
    
    my $src = '\\' . $type . $remote_var . ";\n";
    my $r = $self->call_eval($src);
    die $@ if $@;
    $src = '*' . $local_var . ' = $r' . ";\n";
    eval $src;
    die $@ if $@;
    return 1;
}

# this proxies an entire class instead of just a single object

sub _bind_local_class_to_remote {
    my $self = shift;
    my ($class,$module,$path,@exported) = $self->call_use(@_);
    my $re_bind = 0;
    if (my $prior = $RMI::proxied_classes{$class}) {
        if ($prior != $self) {
            die "class $class has already been proxied by another RMI client: $prior!";
        }
        else {
            # re-binding a class to the same remote side doesn't hurt,
            # and allowing it allows the effect of export to occur
            # in multiple places on the client side.
        }
    }
    elsif (my $path = $INC{$module}) {
        die "module $module has already been used locally from path: $path";
    }
    no strict 'refs';
    for my $sub (qw/AUTOLOAD DESTROY can isa/) {
        *{$class . '::' . $sub} = \&{ 'RMI::ProxyObject::' . $sub }
    }
    if (@exported) {
        my $caller ||= caller(0);
        if (substr($caller,0,5) eq 'RMI::') { $caller = caller(1) }
        for my $sub (@exported) {
            my @pair = ('&' . $caller . '::' . $sub => '&' . $class . '::' . $sub);
            print "$RMI::DEBUG_MSG_PREFIX N: $$ bind pair $pair[0] $pair[1]\n" if $RMI::DEBUG;
            $self->_bind_local_var_to_remote(@pair);
        }
    }
    $RMI::proxied_classes{$class} = $self;
    $INC{$module} = -1; #$path;
    print "$class used remotely via $self.  Module $module found at $path remotely.\n" if $RMI::DEBUG;    
}

=pod

=head1 NAME

RMI::Client - connection to an RMI::Server

=head1 SYNOPSIS

 # simple
 $c = RMI::Client::ForkedPipes->new(); 

 # typical
 $c = RMI::Client::Tcp->new(host => 'server1', port => 1234);
 
 # roll-your-own...
 $c = RMI::Client->new(reader => $fh1, writer => $fh2); # generic
 
 $c->call_use('IO::File');
 $c->call_use('Sys::Hostname');

 $remote_obj = $c->call_class_method('IO::File','new','/tmp/myfile');
 print $remote_obj->getline;
 print <$remote_obj>;

 $host = $c->call_function('Sys::Hostname::hostname')
 $host eq 'server1'; #!
 
 $remote_hashref = $c->call_eval('$main::h = { k1 => 111, k2 => 222, k3 => 333}'); 
 $remote_hashref->{k4} = 444;
 print sort keys %$remote_hashref;
 print $c->call_eval('sort keys %$main::h'); # includes changes!

 $c->use_remote('Sys::Hostname');   # this whole package is on the other side
 $host = Sys::Hostname::hostname(); # possibly not this hostname...

 our $c;
 BEGIN {
    $c = RMI::Client::Tcp->new(port => 1234);
    $c->use_lib_remote;
 }
 use Some::Class;               # remote!
  
=head1 DESCRIPTION

This is the base class for a standard RMI connection to an RMI::Server.

In most cases, you will create a client of some subclass, typically
B<RMI::Client::Tcp> for a network socket, or B<RMI::Client::ForkedPipes>
for a private out-of-process object server.

=head1 METHODS
 
=head2 call_class_method($class, $method, @params)

Does $class->$method(@params) on the remote side.

Calling remote constructors is the primary way to make a remote object.

 $remote_obj = $client->call_class_method('Some::Class','new',@params);
 
 $possibly_another_remote_obj = $remote_obj->some_method(@p);
 
=head2 call_function($fname, @params)

A plain function call made by name to the remote side.  The function name must be fully qualified.

 $c->call_use('Sys::Hostname');
 my $server_hostname = $c->call_function('Sys::Hostname::hostname');

=head2 call_sub($fname, @params)

An alias for call_function();

=head2 call_eval($src,@args)

Calls eval $src on the remote side.

Any additional arguments are set to @_ before eval on the remote side, after proxying.

    my $a = $c->call_eval('@main::x = (11,22,33); return \@main::x;');  # pass an arrayref back
    push @$a, 44, 55;                                                   # changed on the server
    scalar(@$a) == $c->call_eval('scalar(@main::x)');                   # ...true!

=head2 call_use($class)

Uses the Perl package specified on the remote side, making it available for later
calls to call_class_method() and call_function().

 $c->call_use('Some::Package');
 
=head2 call_use_lib($path);

Calls "use lib '$path'" on the remote side.

 $c->call_use_lib('/some/path/on/the/server');
 
=head2 use_remote($class)

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

Exporting does work.  To turn it off, use empty braces as you would empty parens.

 $c->use_remote('Sys::Hostname',[]);

To get this effect (and prevent export of the hostame() function).

 use Sys::Hostname ();

=head2 use_lib_remote($path)

Installs a special handler into the local @INC which causes it to check the remote
side for a class.  If available, it will do use_remote() on that class.

 use A;
 use B; 
 BEGIN { $c->use_remote_lib; }; # do everything remotely from now on if possible...
 use C; #remote!
 use D; #remote!
 use E; #local, b/c not found on the remote side

=head2 bind($varname)

Create a local transparent proxy for a package variable on the remote side.

  $c->bind('$Some::Package::somevar')
  $Some::Package::somevar = 123; # changed remotely
  
  $c->bind('@main::foo');
  push @main::foo, 11, 22 33; #changed remotely

=head1 EXAMPLES

=head2 creating and using a remote hashref

This makes a hashref on the server, and makes a proxy on the client:

    my $remote_hashref = $c->call_eval('{}');

This seems to put a key in the hash, but actually sends a message to the server
to modify the hash.

    $remote_hashref->{key1} = 100;

Lookups also result in a request to the server:

    print $remote_hashref->{key1};

When we do this, the hashref on the server is destroyed, as since the ref-count
on both sides is now zero:

    $remote_hashref = undef;

=head2 making a remote CODE ref, and using it with local and remote objects

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

=head1 BUGS AND CAVEATS

See general bugs in B<RMI> for general system limitations

=head1 SEE ALSO

B<RMI>, B<RMI::Client::Tcp>, B<RMI::Server>

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

