
package RMI::ProxyObject;

sub AUTOLOAD {
    my $object = shift;
    my $method = $AUTOLOAD;
    $method =~ s/^.*:://g;    
    my $node = $RMI::Node::node_for_object{"$object"};
    print "$RMI::DEBUG_INDENT P: $$ $object $method redirecting to node $node\n" if $RMI::DEBUG;
    $node->_call($object, $method, @_);
}

sub DESTROY {
    my $self = $_[0];
    my $id = "$self";
    my $node = $RMI::Node::node_for_ojbect{$id};
    print "DESTROYING $id from $node\n" if $RMI::DEBUG;
    my $other_ref = delete $self->{received}{$id};
    unless ($other_ref) {
        print "NOT ON RECORD AS RECEIVED?";
    }
    $self->SUPER::DESTROY(@_);
}

1;

