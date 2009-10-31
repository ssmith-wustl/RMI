package RMI::ProxyObject::DBI::db;

sub selectall_arrayref {
    no strict;
    my $object = shift;
    my ($class,$method) = ('DBI::db','selectall_arrayref');
    no warnings;
    my $node = $RMI::Node::node_for_object{$object} || $RMI::proxied_classes{$class};
    unless ($node) {
        die "no node for object $object: cannot call $method(@_)?" . Data::Dumper::Dumper(\%RMI::Node::node_for_object);
    }
    print "$RMI::DEBUG_MSG_PREFIX O: $$ $object $method redirecting to node $node\n" if $RMI::DEBUG;
    $node->send_request_and_receive_response({ copy => 1 }, (ref($object) ? 'call_object_method' : 'call_class_method'), ($object||$class), $method, @_);
}

1;

