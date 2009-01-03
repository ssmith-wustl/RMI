
package RMI::ProxyReference;
use strict;
use warnings;   

*TIEARRAY   = \&TIE;
*TIEHASH    = \&TIE;
*TIESCALAR  = \&TIE;

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
    $node->_send(undef, $delegate_class . '::' . $method, @_);
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
