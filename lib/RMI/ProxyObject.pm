
package RMI::ProxyObject;
use strict;
use warnings;

sub AUTOLOAD {
    no strict;
    my $object = shift;
    my $method = $AUTOLOAD;
    $method =~ s/^.*:://g;    
    my $node = $RMI::Node::node_for_object{"$object"};
    unless ($node) {
        die "no node for object $object?" . Data::Dumper::Dumper(\%RMI::Node::node_for_object);
    }
    print "$RMI::DEBUG_INDENT P: $$ $object $method redirecting to node $node\n" if $RMI::DEBUG;
    $node->_send($object, $method, @_);
}

sub DESTROY {
    my $self = $_[0];
    my $id = "$self";
    my $remote_id = $$self;
    my $node = delete $RMI::Node::node_for_object{$id};
    print "$RMI::DEBUG_INDENT P: $$ DESTROYING $id wrapping $remote_id from $node\n" if $RMI::DEBUG;
    my $other_ref = delete $node->{_received_objects}{$remote_id};
    if (!$other_ref and !$RMI::process_is_ending) {
        warn "$RMI::DEBUG_INDENT P: $$ DESTROYING $id wrapping $remote_id from $node NOT ON RECORD AS RECEIVED DURING DESTRUCTION?!\n"
            . Data::Dumper::Dumper($node->{_received_objects});
    }
    push @{ $node->{_received_and_destroyed_ids} }, $remote_id;
}

1;

