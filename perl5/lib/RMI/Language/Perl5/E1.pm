package RMI::Language::Perl5::E1;
use strict;
use warnings;

our $value = 0;
our $blessed_reference = 1;
our $unblessed_reference = 2;
our $return_proxy = 3;

# encode for a Perl5::E1 remote node
sub encode {
    my ($self, $message_data, $opts) = @_;
      
    my $sent_objects = $self->{_sent_objects};    
    my @encoded;
    for my $o (@$message_data) {
        if (my $type = ref($o)) {
            # sending some sort of reference
            if (my $remote_id = $RMI::Node::remote_id_for_object{$o}) { 
                # this is a proxy object on THIS side: the real object will be used on the remote side
                print "$RMI::DEBUG_MSG_PREFIX N: $$ proxy $o references remote $remote_id:\n" if $RMI::DEBUG;
                push @encoded, $RMI::Language::Perl5::E1::return_proxy, $remote_id;
                next;
            }
            elsif($opts and ($opts->{copy} or $opts->{copy_params})) {
                # a reference on this side which should be copied on the other side instead of proxied
                # this never happens by default in the RMI modules, only when specially requested for performance
                # or to get around known bugs in the C<->Perl interaction in some modules (DBI).
                $o = $self->_create_remote_copy($o);
                redo;
            }
            else {
                # a reference originating on this side: send info so the remote side can create a proxy

                # TODO: use something better than stringification since this can be overridden!!!
                my $local_id = "$o";
                
                # TODO: handle extracting the base type for tying for regular objects which does not involve parsing
                my $base_type = substr($local_id,index($local_id,'=')+1);
                $base_type = substr($base_type,0,index($base_type,'('));
                my $code;
                if ($base_type ne $type) {
                    # blessed reference
                    $code = $RMI::Language::Perl5::E1::blessed_reference;
                    if (my $allowed = $self->{allow_packages}) {
                        unless ($allowed->{ref($o)}) {
                            die "objects of type " . ref($o) . " cannot be passed from this RMI node!";
                        }
                    }
                }
                else {
                    # regular reference
                    $code = $RMI::Language::Perl5::E1::unblessed_reference;
                }
                
                push @encoded, $code, $local_id;
                $sent_objects->{$local_id} = $o;
            }
        }
        else {
            # sending a non-reference value
            push @encoded, $RMI::Language::Perl5::E1::value, $o;
        }
    }

    return @encoded;
}

# decode from a Perl5::E1 remote node
sub decode {
    my ($self, $encoded) = @_;
    
    my @message_data;

    my $sent_objects = $self->{_sent_objects};
    my $received_objects = $self->{_received_objects};
    
    while (@$encoded) { 
        my $type = shift @$encoded;
        my $value = shift @$encoded;
        if ($type == 0) {
            # primitive value
            print "$RMI::DEBUG_MSG_PREFIX N: $$ - primitive " . (defined($value) ? $value : "<undef>") . "\n" if $RMI::DEBUG;
            push @message_data, $value;
        }
        elsif ($type == 1 or $type == 2) {
            # exists on the other side: make a proxy
            my $o = $received_objects->{$value};
            unless ($o) {
                my ($remote_class,$remote_shape) = ($value =~ /^(.*?=|)(.*?)\(/);
                chop $remote_class;
                my $t;
                if ($remote_shape eq 'ARRAY') {
                    $o = [];
                    $t = tie @$o, 'RMI::ProxyReference', $self, $value, "$o", 'Tie::StdArray';                        
                }
                elsif ($remote_shape eq 'HASH') {
                    $o = {};
                    $t = tie %$o, 'RMI::ProxyReference', $self, $value, "$o", 'Tie::StdHash';                        
                }
                elsif ($remote_shape eq 'SCALAR') {
                    my $anonymous_scalar;
                    $o = \$anonymous_scalar;
                    $t = tie $$o, 'RMI::ProxyReference', $self, $value, "$o", 'Tie::StdScalar';                        
                }
                elsif ($remote_shape eq 'CODE') {
                    my $sub_id = $value;
                    $o = sub {
                        $self->send_request_and_receive_response('call_coderef', '', '', $sub_id, @_);
                    };
                    # TODO: ensure this cleans up on the other side when it is destroyed
                }
                elsif ($remote_shape eq 'GLOB' or $remote_shape eq 'IO') {
                    $o = \do { local *HANDLE };
                    $t = tie *$o, 'RMI::ProxyReference', $self, $value, "$o", 'Tie::StdHandle';
                }
                else {
                    die "unknown reference type for $remote_shape for $value!!";
                }
                if ($type == 1) {
                    if ($RMI::proxied_classes{$remote_class}) {
                        bless $o, $remote_class;
                    }
                    else {
                        # Put the object into a custom subclass of RMI::ProxyObject
                        # this allows class-wide customization of how proxying should
                        # occur.  It also makes Data::Dumper results more readable.
                        my $target_class = 'RMI::Proxy::' . $remote_class;
                        unless ($RMI::classes_with_proxied_objects{$remote_class}) {
                            no strict 'refs';
                            @{$target_class . '::ISA'} = ('RMI::ProxyObject');
                            no strict;
                            no warnings;
                            local $SIG{__DIE__} = undef;
                            local $SIG{__WARN__} = undef;
                            eval "use $target_class";
                            $RMI::classes_with_proxied_objects{$remote_class} = 1;
                        }
                        bless $o, $target_class;    
                    }
                }
                $received_objects->{$value} = $o;
                Scalar::Util::weaken($received_objects->{$value});
                my $o_id = "$o";
                my $t_id = "$t" if defined $t;
                $RMI::Node::node_for_object{$o_id} = $self;
                $RMI::Node::remote_id_for_object{$o_id} = $value;
                if ($t) {
                    # ensure calls to work with the "tie-buddy" to the reference
                    # result in using the orinigla reference on the "real" side
                    $RMI::Node::node_for_object{$t_id} = $self;
                    $RMI::Node::remote_id_for_object{$t_id} = $value;
                }
            }
            
            push @message_data, $o;
            print "$RMI::DEBUG_MSG_PREFIX N: $$ - made proxy for $value\n" if $RMI::DEBUG;
        }
        elsif ($type == 3) {
            # exists on this side, and was a proxy on the other side: get the real reference by id
            my $o = $sent_objects->{$value};
            my $msg = "$RMI::DEBUG_MSG_PREFIX N: $$ reconstituting local object $value, but not found in my sent objects!\n";
            print $msg and Carp::confess($msg) unless $o;
            push @message_data, $o;
            print "$RMI::DEBUG_MSG_PREFIX N: $$ - resolved local object for $value\n" if $RMI::DEBUG;
        }
        else {
            die "Unknown type $type????"
        }
    }

    return \@message_data;
}

=pod

=head1 NAME

RMI::Language::Perl5::E1

=head1 VERSION

This document describes RMI::Language::Perl5::E1 v0.11.

=head1 DESCRIPTION

The RMI::Language::Perl5::E1 module handles encode/decode for RMI nodes where
the remote node is a Perl5::E1 node.  All modules in the RMI::Language::*
namepace handle various remote languages for a Perl 5 client, and this one
is the default which handles a client of the same language.

=head1 METHODS

=head2 encode

Turns an array of real data values which contain references into an array
of values which contains no references.

=head2 decode

Takes an array made by encode on the other side, and turns it into an array
which functions like the one which was originally encoded.

=head2 ENCODING

An array of message_data of length n to is converted to have a length of n*2.
Each value is preceded by an integer which categorizes the value.

  0    a primitive, non-reference value
       
       The value itself follows, it is not a reference, and it is passed by-copy.
       
  1    an object reference originating on the sender's side
 
       A unique identifier for the object follows instead of the object.
       The remote side should construct a transparent proxy which uses that ID.
       
  2    a non-object (unblessed) reference originating on the sender's side
       
       A unique identifier for the reference follows, instead of the reference.
       The remote side should construct a transparent proxy which uses that ID.
       
  3    passing-back a proxy: a reference which originated on the receiver's side
       
       The following value is the identifier the remote side sent previously.
       The remote side should substitue the original object when deserializing

=head1 SEE ALSO

B<RMI>, B<RMI::Node>

=head1 AUTHORS

Scott Smith <sakoht@cpan.org>

=head1 COPYRIGHT

Copyright (c) 2008 - 2010 Scott Smith <sakoht@cpan.org>  All rights reserved.

=head1 LICENSE

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

The full text of the license can be found in the LICENSE file included with this
module.

=cut

1;


