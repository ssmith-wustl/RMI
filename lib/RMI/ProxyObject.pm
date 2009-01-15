package RMI::ProxyObject;

use strict;
use warnings;
use version;
our $VERSION = qv('0.1');

use RMI;

sub AUTOLOAD {
    no strict;
    my $object = shift;
    my $method = $AUTOLOAD;
    my ($class,$subname) = ($method =~ /^(.*)::(.*?)$/);
    $method = $subname;
    no warnings;
    my $node = $RMI::Node::node_for_object{$object} || $RMI::Node::proxied_classes{$class};
    unless ($node) {
        die "no node for object $object: cannot call $method(@_)?" . Data::Dumper::Dumper(\%RMI::Node::node_for_object);
    }
    print "$RMI::DEBUG_MSG_PREFIX O: $$ $object $method redirecting to node $node\n" if $RMI::DEBUG;
    $node->send_request_and_receive_response(($object||$class), $method, @_);
}

sub can {
    my $object = shift;
    my $node = $RMI::Node::node_for_object{$object} || $RMI::Node::proxied_classes{$object};
    unless ($node) {
        die "no node for object $object: cannot call can (@_)" . Data::Dumper::Dumper(\%RMI::Node::node_for_object);
    }
    print "$RMI::DEBUG_MSG_PREFIX O: $$ $object 'can' redirecting to node $node\n" if $RMI::DEBUG;
    $node->send_request_and_receive_response($object, 'can', @_);
}

sub isa {
    my $object = shift;
    my $node = $RMI::Node::node_for_object{$object} || $RMI::Node::proxied_classes{$object};
    unless ($node) {
        die "no node for object $object: cannot call isa (@_)" . Data::Dumper::Dumper(\%RMI::Node::node_for_object);
    }
    print "$RMI::DEBUG_MSG_PREFIX O: $$ $object 'isa' redirecting to node $node\n" if $RMI::DEBUG;
    $node->send_request_and_receive_response($object, 'isa', @_);
}

sub DESTROY {
    my $self = $_[0];
    my $id = "$self";
    my $remote_id = delete $RMI::Node::remote_id_for_object{$id};
    my $node = delete $RMI::Node::node_for_object{$id};
    print "$RMI::DEBUG_MSG_PREFIX O: $$ DESTROYING $id wrapping $remote_id from $node\n" if $RMI::DEBUG;
    my $other_ref = delete $node->{_received_objects}{$remote_id};
    if (!$other_ref and !$RMI::process_is_ending) {
        warn "$RMI::DEBUG_MSG_PREFIX O: $$ DESTROYING $id wrapping $remote_id from $node NOT ON RECORD AS RECEIVED DURING DESTRUCTION?!\n"
            . Data::Dumper::Dumper($node->{_received_objects});
    }
    push @{ $node->{_received_and_destroyed_ids} }, $remote_id;
}

1;

=pod

=head1 NAME

RMI::ProxyObject - used internally by RMI::Node to create proxy stubs
    
=head1 DESCRIPTION

The full explanation of how references, blessed and otherwise, are
proxied across an RMI::Client/RMI::Server pair (or any RMI::Node pair)
is in B<RMI::ProxyReference>.

When the object to be proxied is blessed into a class, the proxy
is blessed into the RMI::RemoteProxy class.

Note that RMI::ProxyObjects are also "tied" to the package B<RMI::ProxyReference>,
which handles attempts to use the reference as a plain Perl reference.

=head1 METHODS

This class implements
AUTOLOAD, and directs all method calls across the connection which
created it to the remote side for actual execution.

It also overrides isa() and can() to simulate the class
it represents.

=head1 BUGS AND CAVEATS

=over 

=item the object is not 100% transparent

Ways to detect that an object is an RMI::ProxyObject are:
 1. ref($obj) will return "RMI::ProxyObject" unless the entire class
has been proxied (with $client->use_remote('SomeClass').
 2. "$obj" will stringify to "RMI::ProxyObject=SOMETYPE(...)", though
this will probaby be changed at a future date.

See general bugs in B<RMI> for general system limitations of proxied objects.

=back

=head1 SEE ALSO

B<RMI>, B<RMI::ProxyReference>, B<RMI::Node>

=cut

