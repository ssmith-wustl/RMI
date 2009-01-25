package RMI::Server;

use strict;
use warnings;
use version;
our $VERSION = qv('0.1');

use base 'RMI::Node';

sub run {
    my($self) = @_;
    while(1) {
        last if $self->{is_closed}; 
        last unless $self->receive_request_and_send_response();
    }
    return 1;
}

# REMOTE CALLBACKS

# While these are logically methods on the server, they are the 
# by the client to prevent the client from directly addressing
# server internals.  They are invoked by comparable call_* methods
# in the client class.

sub _receive_use {
    my $self = $RMI::executing_nodes[-1];
    my ($class,$module,$has_args,@use_args) = @_;
    
    no strict 'refs';
    if ($class and not $module) {
        $module = $class;
        $module =~ s/::/\//g;
        $module .= '.pm';
    }
    elsif ($module and not $class) {
        $class = $module;
        $class =~ s/\//::/g;
        $class =~ s/.pm$//; 
    }
    #print "using $class/$module with args " . Data::Dumper::Dumper($has_args);
    
    my $n = $RMI::Exported::count++;
    my $tmp_package_to_catch_exports = 'RMI::Exported::P' . $n;
    my $src = "
        package $tmp_package_to_catch_exports;
        require $class;
        my \@exports = ();
        if (\$has_args) {
            if (\@use_args) {
                $class->import(\@use_args);
                \@exports = grep { ${tmp_package_to_catch_exports}->can(\$_) } keys \%${tmp_package_to_catch_exports}::;
            }
            else {
                # print qq/no import because of empty list!/;
            }
        }
        else {
            $class->import();
            \@exports = grep { ${tmp_package_to_catch_exports}->can(\$_) } keys \%${tmp_package_to_catch_exports}::;
        }
        return (\$INC{'$module'}, \@exports);
    ";
    #print "eval with params!  count: " . scalar(@use_args) . " values: @use_args\n" if $has_args;
    #print $src;
    my ($path, @exported) = eval($src);
    die $@ if $@;
    #print "got " . Data::Dumper::Dumper($path,\@exported);
    return ($class,$module,$path,@exported);
}

sub _receive_use_lib {
    my $self = $RMI::executing_nodes[-1];
    my $lib = shift;
    require lib;
    return lib->import($lib);
}

sub _receive_eval {
    my $src = shift;
    if (wantarray) {
        my @result = eval $src;
        die $@ if $@;
        return @result;        
    }
    else {
        my $result = eval $src;
        die $@ if $@;
        return $result;
    }
}


1;

=pod

=head1 NAME

RMI::Server - service remote RMI requests

=head1 SYNOPSIS

    $s = RMI::Server->new(
        reader => $fh1,
        writer => $fh2,
    );
    $s->run;

    $s = RMI::Server::Tcp->new(
        port => 1234
    );
    $s->run;

    $s = RMI::Server->new(...);
    for (1..3) {
        $s->receive_request_and_send_response;
    }
    
=head1 DESCRIPTION

This is the base class for RMI::Servers, which accept requests
via an IO handle of some sort, execute code on behalf of the
request, and send the return value back to the client.

When the RMI::Server responds to a request which returns objects or references,
the items in question are not serialized back to the client.  Instead the client
recieves an identifier, and creates a proxy object which uses the client
to delegate method calls to its counterpart on the server.

When objects or references are sent to an RMI server as parameters, the server
creates a proxy to represent them, and the client in effect becomes the
server for those proxy objects.  The real reference stays on the client,
and all interaction with the item in question during the invocation
result in counter-requests being sent back to the client for method
resolution on that end.

See the detailed explanation of remote proxy references in the B<RMI> general
documentation.

=head1 METHODS

=over 4

=item new()

 $s = RMI::Server->new(reader => $fh1, writer => $fh2)

This is typically overriden in a specific subclass of RMI::Server to construct
the reader and writer according to a particular strategy.  It is possible for
the reader and the writer to be the same handle, particularly for B<RMI::Server::Tcp>.

=item receive_request_and_send_response()

 $bool = $

Implemented in the base class for all RMI::Node objects, this handles processing
a single request from the reader handle.

=item run()

 $s->run();
 
Enter a loop processing RMI requests.  This will continue as long as the
connection is open.

=back

=head1 BUGS AND CAVEATS

See general bugs in B<RMI> for general system limitations

=head1 SEE ALSO

B<RMI> B<RMI::Node> B<RMI::Client> B<RMI::Server::Tcp> B<RMI::Server::ForkedPipes>

=cut
