
package RMI::ProxyObject;

sub AUTOLOAD {
    my $object = shift;
    my $method = $AUTOLOAD;
    $method =~ s/^.*:://g;

    
    my $key = $RMI::server_id_for_remote_object{$object};
    my $server = $RMI::server_for_id{$key};

    my $node = $RMI::Node::node_for_object{"$object"};

    die "No server $server for key $key!?" unless $server and @$server == 4;
    print "$RMI::DEBUG_INDENT P: $$ $object $method : @$server\n" if $RMI::DEBUG;
    if (wantarray) {
        my @r = RMI::Node::_call($node,@$server, $object, $method, @_); 
        return @r;
    }
    else {
        my $r = RMI::Node::_call($node,@$server, $object, $method, @_); 
        return $r;
    }
}

sub DESTROY {
    
}

1;

