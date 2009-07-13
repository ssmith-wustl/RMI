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
    my $node = $RMI::Node::node_for_object{$object} || $RMI::proxied_classes{$class};
    unless ($node) {
        die "no node for object $object: cannot call $method(@_)?" . Data::Dumper::Dumper(\%RMI::Node::node_for_object);
    }
    print "$RMI::DEBUG_MSG_PREFIX O: $$ $object $method redirecting to node $node\n" if $RMI::DEBUG;
    $node->send_request_and_receive_response((ref($object) ? 'call_object_method' : 'call_class_method'), ($object||$class), $method, \@_);
}

sub can {
    my $object = shift;
    my $node = $RMI::Node::node_for_object{$object} || $RMI::proxied_classes{$object};
    unless ($node) {
        die "no node for object $object: cannot call can (@_)" . Data::Dumper::Dumper(\%RMI::Node::node_for_object);
    }
    print "$RMI::DEBUG_MSG_PREFIX O: $$ $object 'can' redirecting to node $node\n" if $RMI::DEBUG;
    $node->send_request_and_receive_response((ref($object) ? 'call_object_method' : 'call_class_method'), $object, 'can', \@_);
}

sub isa {
    my $object = shift;
    my $node = $RMI::Node::node_for_object{$object} || $RMI::proxied_classes{$object};
    unless ($node) {
        die "no node for object $object: cannot call isa (@_)" . Data::Dumper::Dumper(\%RMI::Node::node_for_object);
    }
    print "$RMI::DEBUG_MSG_PREFIX O: $$ $object 'isa' redirecting to node $node\n" if $RMI::DEBUG;
    $node->send_request_and_receive_response((ref($object) ? 'call_object_method' : 'call_class_method'), $object, 'isa', \@_);
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

RMI::ProxyObject - a transparent proxy to a remote object
    
=head1 DESCRIPTION

Any time an RMI::Client or RMI::Server "passes" an object as a parameter 
or a return value, an RMI::ProxyObject is created on the other side.  

These are not constructed by directly calling methods of this class.  
Construction of RMI::ProxyObjects is internal to RMI::Node operation.

Note that RMI::ProxyObjects are also "tied" to the package 
B<RMI::ProxyReference>, which handles attempts to use the reference 
as a plain Perl reference.

The full explanation of how references, blessed and otherwise, are
proxied across an RMI::Client/RMI::Server pair (or any RMI::Node pair)
is in B<RMI::ProxyReference>.

=head1 METHODS

The goal of objects of this class is to simulate a specific object
on the other side of a specific RMI::Node (RMI::Client or RMI::Server).

As such, it does not have its own API.  It overrides the four key
methods in ways which are key to its ability to delegate:

=over 4

=item AUTOLOAD

This class implements AUTOLOAD, and directs all method calls across the 
connection which created it to the remote side for actual execution.

=item isa

Since calls to isa() will not fire AUTOLOAD, we override isa() explicitly
to redirect through the RMI::Node which owns the object in question.

=item can 

Since calls to can() will also not fire AUTOLOAD, we override can() explicitly
to redirect through the RMI::Node which owns the object in question.

=item DESTROY

The DESTROY handler manages ensuring that the remote side reduces its reference
count and can do correct garbage collection.

=back

=head1 BUGS AND CAVEATS

=over 

=item the proxy object is not 100% transparent

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

