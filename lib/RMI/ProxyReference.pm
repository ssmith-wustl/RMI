
package RMI::ProxyReference;
use strict;
use warnings;   

# When references are "passed" to a remote client/server, the proxy is tied using this package to proxy back all data access.
# NOTE: if the reference is blessed, the proxy will also be blessed into RMI::ProxyObject, in addition to being _tied_ to this package.

*TIEARRAY   = \&TIE;
*TIEHASH    = \&TIE;
*TIESCALAR  = \&TIE;

# CODE references are handled specially, using an anonymous sub on the proxy side, without tie, since tie does not support them
# GLOBs are not supported at this point

sub TIE {
    my $obj = bless [@_], $_[0];
    return $obj;
}

sub AUTOLOAD {
    no strict 'refs';
    my $method = $RMI::ProxyReference::AUTOLOAD;
    $method =~ s/^.*:://g;
    my $o = $_[0];
    my ($c,$n,$v,$t,$delegate_class) = @$o;
    my $node = $RMI::Node::node_for_object{$t} || $n;
    print "$RMI::DEBUG_INDENT R: $$ array $method from $o ($n,$v,$t) redirecting to node $node with @_\n" if $RMI::DEBUG;
    unless ($node) {
        die "no node for reference $o: method $method for @_ (@$o)?" . Data::Dumper::Dumper(\%RMI::Node::node_for_object);
    }
    $node->send_request_and_receive_response(undef, $delegate_class . '::' . $method, @_);
}

sub DESTROY {
    my $self = $_[0];
    my ($c,$node,$remote_id,$t) = @$self;
    $node = delete $RMI::Node::node_for_object{$t};
    print "$RMI::DEBUG_INDENT R: $$ DESTROYING $self wrapping $remote_id from $node with $t\n" if $RMI::DEBUG;
    my $other_ref = delete $node->{_received_objects}{$remote_id};
    if (!$other_ref and !$RMI::process_is_ending) {
        #warn "$RMI::DEBUG_INDENT R: $$ DESTROYING $self wrapping $remote_id from $node NOT ON RECORD AS RECEIVED DURING DESTRUCTION?!\n"
        #    . Data::Dumper::Dumper($node->{_received_objects});
    }
    push @{ $node->{_received_and_destroyed_ids} }, $remote_id;
}

1;
