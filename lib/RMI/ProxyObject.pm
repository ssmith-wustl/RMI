
package RMI::ProxyObject;

sub AUTOLOAD {
    my $object = shift;
    my $method = $AUTOLOAD;
    $method =~ s/^.*:://g;
    
    my $key = $RMI::server_for_object{$object};
    my $server = $RMI::server_for_key{$key};
    die unless $server and @$server == 4;
    print "$RMI::DEBUG_INDENT P: $$ $object $method : @$server\n" if $RMI::DEBUG;
    if (wantarray) {
        my @r = RMI::call(@$server, $object, $method, @_); 
        return @r;
    }
    else {
        my $r = RMI::call(@$server, $object, $method, @_); 
        return $r;
    }
}

sub DESTROY {
    
}

package RMI::ProxyObject::Util;

1;

