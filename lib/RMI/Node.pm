package RMI::Node;
use strict;
use warnings;
use RMI;
use Scalar::Util;
use Tie::Array;
use Tie::Hash;
use Tie::Scalar;

# public interface

my @p = qw/reader writer peer_pid _sent_objects _received_objects _received_and_destroyed_ids _tied_objects/;
for my $p (@p) {
    my $pname = $p;
    no strict 'refs';
    *$p = sub { $_[0]->{$pname} };
}

# this stack is used for debugging methods
our @executing_nodes;

sub new {
    my $class = shift;
    my $self = bless {
        _sent_objects => {},
        _received_objects => {},
        _received_and_destroyed_ids => [],
        _tied_objects => {},
        @_
    }, $class;
    for my $p (@p) {
        unless ($self->{$p}) {
            die "no $p on object!"
        }
    }    
    return $self;
}

sub close {
    my $self = $_[0];
    $self->{reader}->close;
    $self->{writer}->close;
}

# the real work is done by 4 methods

sub _send {
    my ($self, $o, $m, @p) = @_;

    my $hout = $self->{writer};
    my $hin = $self->{reader};
    my $sent_objects = $self->{_sent_objects};
    my $received_objects = $self->{_received_objects};
    my $received_and_destroyed_ids = $self->{_received_and_destroyed_ids};
    my $os = $o || '<none>';
    my $wantarray = wantarray;

    print "$RMI::DEBUG_INDENT C: $$ calling via $self on $os: $m with @p\n" if $RMI::DEBUG;

    # pacakge the call and params for transmission
    my @px = $self->_serialize($sent_objects,$received_objects,$received_and_destroyed_ids,[$o,@p]);
    my $s = Data::Dumper::Dumper(['query',$m,@px]);
    $s =~ s/\n/ /gms;
    print "$RMI::DEBUG_INDENT C: $$ sending $s\n" if $RMI::DEBUG;
    
    # send it
    my $r = $hout->print($s,"\n");
    unless ($r) {
        die "failed to send! $!";
    }
    
    # the process of getting the answer involves
    # becoming a server to the other side during the call
    my @result = $self->_receive('result');
 
    if ($wantarray) {
        return @result;        
    }
    else {
        return $result[0];    
    }
}

sub _receive {
    my ($self, $expect) = @_;
    
    # The $expect value determines the _last_ thing
    # which should happen before we return as a sanity check.
    
    # when called from a server, expect is typically 'query'
    # when called from a client, expect is typically 'result'
    
    # besides the final action, the work is the same:
    #  sit in a loop getting messages from the other side
    #  doing whatever the other side demands until they
    #  give a result (if we are a client who sent_objects a query)
    #  or return undef telling us to shut down (if we are a server)
    
    my $hin = $self->{reader};
    my $hout = $self->{writer};
    my $sent_objects = $self->{_sent_objects};
    my $received_objects = $self->{_received_objects};
    my $received_and_destroyed_ids = $self->{_received_and_destroyed_ids};
    my $peer_pid = $self->{peer_pid};
    
    while (1) {
        print "$RMI::DEBUG_INDENT X: $$ receiving\n" if $RMI::DEBUG;
        my $incoming_text = $hin->getline;
        if (not defined $incoming_text) {
            if ($expect eq 'result') {
                die "$RMI::DEBUG_INDENT X: $$ connection failure before result returned!";
            }
            else {
                print "$RMI::DEBUG_INDENT X: $$ shutting down\n" if $RMI::DEBUG;
                last;
            }
        }
        print "$RMI::DEBUG_INDENT X: $$ got $incoming_text" if $RMI::DEBUG;
        print "\n" if $RMI::DEBUG and not defined $incoming_text;
        my $incoming_data = eval "no strict; no warnings; $incoming_text";
        if ($@) {
            die "Exception: $@";
        }

        my $type = shift @$incoming_data;
        if ($type eq 'result') {
            if ($expect eq 'query') {
                die "$RMI::DEBUG_INDENT X: $$ recieved result directly from client?!";
            }
            print "$RMI::DEBUG_INDENT X: $$ returning @$incoming_data\n" if $RMI::DEBUG;
            return $self->_deserialize($sent_objects,$received_objects,@$incoming_data);            
        }
        elsif ($type eq 'deref') {
            $self->_deserialize($sent_objects,$received_objects,@$incoming_data)
        }
        elsif ($type eq 'query') {
            no warnings;
            print "$RMI::DEBUG_INDENT X: $$ processing (serialized): @$incoming_data\n" if $RMI::DEBUG;
            my ($m,@px) = @$incoming_data;
            my @p = $self->_deserialize($sent_objects,$received_objects,@px);
            my $o = shift @p;
            print "$RMI::DEBUG_INDENT X: $$ unserialized object $o and params: @p\n" if $RMI::DEBUG;
            my @result;
            push @executing_nodes, $self;
            if (defined $o) {
                @result = $o->$m(@p);
            }
            else {
                no strict 'refs';
                @result = $m->(@p);
            }
            pop @executing_nodes;
            # we MUST undef these in case they are the only references to objects which need to be destroyed
            $o = undef;
            @p = ();
            print "$RMI::DEBUG_INDENT X: $$ executed with result (unserialized): @result\n" if $RMI::DEBUG;
            my @serialized = $self->_serialize($sent_objects, $received_objects, $received_and_destroyed_ids, \@result);
            print "$RMI::DEBUG_INDENT X: $$ result serialized as @serialized\n" if $RMI::DEBUG;
            my $s = Data::Dumper::Dumper(['result', @serialized]);
            @$received_and_destroyed_ids = ();
            $s =~ s/\n/ /gms;
            $hout->print($s,"\n");
        }
        else {
            die "unexpected type $type";
        }
    }
}

sub _serialize {
    my ($self,$sent_objects,$received_objects,$received_and_destroyed_ids,$unserialized_values_arrayref) = @_;    
    my @serialized = ([@$received_and_destroyed_ids]);
    @$received_and_destroyed_ids = ();
    my $type;
    for my $o (@$unserialized_values_arrayref) {
        if ($type = ref($o)) {
            if ($type eq "RMI::ProxyObject") {
                my $key = $RMI::Node::remote_id_for_object{$o};
                $key ||= $$o;
                print "$RMI::DEBUG_INDENT X: $$ proxy $o references remote $key:\n" if $RMI::DEBUG;
                push @serialized, 2, $key;
                next;
            }
            elsif ($type eq "RMI::ProxyReference") {
                my $key = $RMI::Node::remote_id_for_object{$o};
                $key ||= $o->[2];
                print "$RMI::DEBUG_INDENT X: $$ tied proxy special obj $o references remote $key:\n" if $RMI::DEBUG;
                push @serialized, 2, $key;
                next;
            }            
            elsif (my $t = $self->{_tied_objects}{$o}) {
                # real array is on the other side
                my $key = $t; #$RMI::Node::remote_id_for_object{$o};
                print "$RMI::DEBUG_INDENT X: $$ tied proxy ref $o ($t) references remote $key (@$t):\n" if $RMI::DEBUG;
                push @serialized, 2, $key;
                next;                
            }
            else {
                # TODO: use something better than stringification since this can be overridden!!!
                my $key = "$o";
                
                # TODO: handle extracting the base type for tying for regular objects which does not involve parsing
                #my $base_type = substr($key,index($key,'=')+1);
                #$base_type = substr($base_type,0,index($base_type,'('));
                #print "base type $base_type for $o\n";                
                if ($type eq 'ARRAY') {
                    my @values = @$o;
                    my $t = tie @$o, 'Tie::Std' . ucfirst(lc($type));
                    @$o = @values;
                    push @serialized, 3, $key;
                }
                elsif ($type eq 'HASH') {
                    my @values = %$o;
                    my $t = tie %$o, 'Tie::Std' . ucfirst(lc($type));
                    %$o = @values;
                    push @serialized, 3, $key;                    
                }
                elsif ($type eq 'SCALAR') {
                    my $value = $$o;
                    my $t = tie $$o, 'Tie::Std' . ucfirst(lc($type));
                    $$o = $value;
                    push @serialized, 3, $key;                                        
                }
                elsif ($type eq 'CODE') {
                    # this doesn't use a class, but gets custom handling
                    push @serialized, 3, $key;
                }
                else {
                    # regular object
                    push @serialized, 1, $key;
                }
                
                $sent_objects->{$key} = $o;               
            }
        }
        else {
            push @serialized, 0, $o;
        }
    }
    @$unserialized_values_arrayref = (); # essential to get the DESTROY handler to fire for proxies we're not holding on-to
    print "$RMI::DEBUG_INDENT X: $$ destroyed proxies: @$received_and_destroyed_ids\n" if $RMI::DEBUG;
    return (@serialized);
}

sub _deserialize {
    my ($self, $sent_objects, $received_objects, $destroyed_remotely, @serialized) = @_;
    my @unserialized;
    while (@serialized) { 
        my $type = shift @serialized;
        my $value = shift @serialized;
        if ($type == 0) {
            # primitive value
            print "$RMI::DEBUG_INDENT S: $$ - primitive " . (defined($value) ? $value : "<undef>") . "\n" if $RMI::DEBUG;
            push @unserialized, $value;
        }   
        elsif ($type == 1 or $type == 3) {
            # exists on the other side: make a proxy
            my $o;
            if ($type == 1) {
                $o = \$value;
                bless $o, "RMI::ProxyObject";
            }
            elsif ($type == 3) {
                $o = $received_objects->{$value};
                unless ($o) {
                    if ($value =~ /^ARRAY/) {
                        $o = [];
                        tie @$o, 'RMI::ProxyReference', $self, $value, "$o", 'Tie::StdArray';                        
                    }
                    elsif ($value =~ /^HASH/) {
                        $o = {};
                        tie %$o, 'RMI::ProxyReference', $self, $value, "$o", 'Tie::StdHash';                        
                    }
                    elsif ($value =~ /^SCALAR/) {
                        my $anonymous_scalar;
                        $o = \$anonymous_scalar;
                        tie $$o, 'RMI::ProxyReference', $self, $value, "$o", 'Tie::StdScalar';                        
                    }
                    elsif ($value =~ /^CODE/) {
                        my $sub_id = $value;
                        $o = sub {
                            $self->_send(undef, 'RMI::Node::_exec_coderef_for_id', $sub_id, @_);
                        }
                    }
                    else {
                        die "unknown reference type for $value!!";
                    }
                }
            }
            $received_objects->{$value} = $o;
            Scalar::Util::weaken($received_objects->{$value});
            push @unserialized, $o;
            $RMI::Node::node_for_object{"$o"} = $self;
            print "$RMI::DEBUG_INDENT S: $$ - made proxy for $value\n" if $RMI::DEBUG;
        }
        elsif ($type == 2) {
            # was a proxy on the other side: get the real object
            my $o = $sent_objects->{$value};
            print "$RMI::DEBUG_INDENT X: $$ reconstituting local object $value, but not found in my sent objects!\n" and die unless $o;
            push @unserialized, $o;
            print "$RMI::DEBUG_INDENT X: $$ - resolved local object for $value\n" if $RMI::DEBUG;
        }
    }
    print "$RMI::DEBUG_INDENT X: $$ remote side destroyed: @$destroyed_remotely\n" if $RMI::DEBUG;
    my @done = grep { defined $_ } delete @$sent_objects{@$destroyed_remotely};
    unless (@done == @$destroyed_remotely) {
        print "Some IDS not found in the sent list: done: @done, expected: @$destroyed_remotely\n";
        
    }
    return @unserialized;    
}

# this allows requests for remote eval to be re-written as a static method call

sub _eval {
    # this wraps Perl eval($src) in a method so that it can be called from the remote side
    my $src = $_[0];
    my @result = eval $src;
    die $@ if $@;
    return @result;
}

sub _exec_coderef_for_id {
    my $sub_id = shift;
    my $sub = $RMI::Node::executing_nodes[-1]{_sent_objects}{$sub_id};
    die "$sub is not a CODE ref.  came from $sub_id\n" unless $sub and ref($sub) eq 'CODE';
    return $sub->(@_);
}



# used for testing

sub _remote_has_ref {
    my ($self,$obj) = @_;
    my $id = "$obj";
    my $has_sent = $self->_send(undef, "RMI::Node::_eval", 'exists $RMI::Node::executing_nodes[-1]->{_received_objects}{"' . $id . '"}');
}

sub _remote_has_sent {
    my ($self,$obj) = @_;
    my $id = "$obj";
    my $has_sent = $self->_send(undef, "RMI::Node::_eval", 'exists $RMI::Node::executing_nodes[-1]->{_sent_objects}{"' . $id . '"}');
}


1;
