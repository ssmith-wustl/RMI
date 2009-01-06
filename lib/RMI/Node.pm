package RMI::Node;
use strict;
use warnings;
use RMI;
use Scalar::Util;
use Tie::Array;
use Tie::Hash;
use Tie::Scalar;

# public API

_mk_ro_accessors(qw/reader writer/);

sub new {
    my $class = shift;
    my $self = bless {
        _sent_objects => {},
        _received_objects => {},
        _received_and_destroyed_ids => [],
        _tied_objects_for_tied_refs => {},
        @_
    }, $class;
    for my $p (@RMI::Node::properties) {
        unless ($self->{$p}) {
            die "no $p on object!"
        }
    }    
    return $self;
}

sub send_request_and_receive_response {
    my $self = shift;
    $self->_send_request(@_);
    my @result = $self->_receive_response; 
    if (wantarray) {
        return @result;        
    }
    else {
        return $result[0];    
    }
}

sub _send_request {
    my ($self, $o, $m, @p) = @_;

    my $hout = $self->{writer};
    my $hin = $self->{reader};
    my $sent_objects = $self->{_sent_objects};
    my $received_objects = $self->{_received_objects};
    my $received_and_destroyed_ids = $self->{_received_and_destroyed_ids};
    my $os = $o || '<none>';

    print "$RMI::DEBUG_INDENT N: $$ calling via $self on $os: $m with @p\n" if $RMI::DEBUG;

    # pacakge the call and params for transmission
    my @px = $self->_serialize($sent_objects,$received_objects,$received_and_destroyed_ids,[$o,@p]);
    my $s = Data::Dumper::Dumper(['query',$m,@px]);
    $s =~ s/\n/ /gms;
    print "$RMI::DEBUG_INDENT N: $$ sending $s\n" if $RMI::DEBUG;
    
    # send it
    my $r = $hout->print($s,"\n");
    unless ($r) {
        die "failed to send! $!";
    }
    return $r;    
}

sub _receive_response {
    my ($self) = @_;    
    for (1) {
        # this will occur once, or more than once if we get a counter-request
        my ($type, $incoming_data) = $self->_read();
        if (not defined $type) {
            die "$RMI::DEBUG_INDENT N: $$ connection failure before result returned!";
        }
        if ($type eq 'result') {
            print "$RMI::DEBUG_INDENT N: $$ returning @$incoming_data\n" if $RMI::DEBUG;
            return $self->_deserialize($incoming_data);            
        }
        elsif ($type eq 'exception') {
            my ($e) = $self->_deserialize($incoming_data);
            die $e;
        }
        elsif ($type eq 'query') {
            $self->_process_query($incoming_data);
            redo;
        }
        else {
            die "unexpected type $type";
        }
    }
    return;
}

sub receive_request_and_send_response {
    my ($self) = @_;    
    for (1) {
        # this will occur once, or more than once if we get a counter-request
        my ($type, $incoming_data) = $self->_read();
        unless (defined $type) {
            print "$RMI::DEBUG_INDENT N: $$ shutting down\n" if $RMI::DEBUG;
            $self->{is_closed} = 1;
            return;
        }
        if ($type eq 'query') {
            $self->_process_query($incoming_data);
            redo;
        }
        else {
            die "$RMI::DEBUG_INDENT N: $$ recieved $type directly from client instead of query?!";
        }
    }
    return;
}

sub _read {
    my ($self) = @_;
    my $hin = $self->{reader};
    my $hout = $self->{writer};
    
    print "$RMI::DEBUG_INDENT N: $$ receiving\n" if $RMI::DEBUG;
    Carp::confess() unless $hin;
    my $incoming_text = $hin->getline;
    if (not defined $incoming_text) {
        return;
    }

    print "$RMI::DEBUG_INDENT N: $$ got $incoming_text" if $RMI::DEBUG;
    print "\n" if $RMI::DEBUG and not defined $incoming_text;
    my $incoming_data = eval "no strict; no warnings; $incoming_text";
    if ($@) {
        die "Exception: $@";
    }        
    my $type = shift @$incoming_data;

    return ($type, $incoming_data);    
}

sub close {
    my $self = $_[0];
    $self->{reader}->close;
    $self->{writer}->close;
}

# the real work is done by 4 methods and 4 tracked data structures

_mk_ro_accessors(qw/_sent_objects _received_objects _received_and_destroyed_ids _tied_objects_for_tied_refs/);

our @executing_nodes; # required for the implementation of proxied CODE references

sub _process_query {
    my ($self,$incoming_data) = @_;

    my $hin = $self->{reader};
    my $hout = $self->{writer};
    my $sent_objects = $self->{_sent_objects};
    my $received_objects = $self->{_received_objects};
    my $received_and_destroyed_ids = $self->{_received_and_destroyed_ids};
    
    no warnings;
    print "$RMI::DEBUG_INDENT N: $$ processing (serialized): @$incoming_data\n" if $RMI::DEBUG;
    my ($m,@px) = @$incoming_data;
    my @p = $self->_deserialize(\@px);
    my $o = shift @p;
    print "$RMI::DEBUG_INDENT N: $$ unserialized object $o and params: @p\n" if $RMI::DEBUG;
    my @result;
    push @executing_nodes, $self;
    eval {
        if (defined $o) {
            @result = $o->$m(@p);
        }
        else {
            no strict 'refs';
            @result = $m->(@p);
        }
    };
    pop @executing_nodes;
    # we MUST undef these in case they are the only references to objects which need to be destroyed
    $o = undef;
    @p = ();
    if ($@) {
        print "$RMI::DEBUG_INDENT N: $$ executed with EXCEPTION (unserialized): $@\n" if $RMI::DEBUG;
        my @serialized = $self->_serialize($sent_objects, $received_objects, $received_and_destroyed_ids, [$@]);
        print "$RMI::DEBUG_INDENT N: $$ EXCEPTION serialized as @serialized\n" if $RMI::DEBUG;
        my $s = Data::Dumper::Dumper(['exception', @serialized]);
        @$received_and_destroyed_ids = ();
        $s =~ s/\n/ /gms;
        $hout->print($s,"\n");                
    }
    else {
        print "$RMI::DEBUG_INDENT N: $$ executed with result (unserialized): @result\n" if $RMI::DEBUG;
        my @serialized = $self->_serialize($sent_objects, $received_objects, $received_and_destroyed_ids, \@result);
        print "$RMI::DEBUG_INDENT N: $$ result serialized as @serialized\n" if $RMI::DEBUG;
        my $s = Data::Dumper::Dumper(['result', @serialized]);
        @$received_and_destroyed_ids = ();
        $s =~ s/\n/ /gms;
        $hout->print($s,"\n");
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
                print "$RMI::DEBUG_INDENT N: $$ proxy $o references remote $key:\n" if $RMI::DEBUG;
                push @serialized, 2, $key;
                next;
            }
            elsif ($type eq "RMI::ProxyReference") {
                # when a proxied reference has activity occur, the object is sent by its tied "object"
                my $key = $RMI::Node::remote_id_for_object{$o};
                $key ||= $o->[2];
                print "$RMI::DEBUG_INDENT N: $$ tied proxy special obj $o references remote $key:\n" if $RMI::DEBUG;
                push @serialized, 2, $key;
                next;
            }            
            elsif (my $t = $self->{_tied_objects_for_tied_refs}{$o}) {
                # when a proxied reference is passed as a parameter or return value, the object sent by its tied "reference"
                my $key = $t; #$RMI::Node::remote_id_for_object{$o};
                print "$RMI::DEBUG_INDENT N: $$ tied proxy ref $o ($t) references remote $key (@$t):\n" if $RMI::DEBUG;
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
    print "$RMI::DEBUG_INDENT N: $$ destroyed proxies: @$received_and_destroyed_ids\n" if $RMI::DEBUG;
    return (@serialized);
}

sub _deserialize {
    my ($self, $serialized) = @_;
    my $sent_objects = $self->{_sent_objects};
    my $received_objects = $self->{_received_objects};
    my $received_and_destroyed_ids = shift @$serialized;
    my @unserialized;
    #Carp::cluck(Data::Dumper::Dumper($serialized));
    while (@$serialized) { 
        my $type = shift @$serialized;
        my $value = shift @$serialized;
        if ($type == 0) {
            # primitive value
            print "$RMI::DEBUG_INDENT N: $$ - primitive " . (defined($value) ? $value : "<undef>") . "\n" if $RMI::DEBUG;
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
                            $self->send_request_and_receive_response(undef, 'RMI::Node::_exec_coderef_for_id', $sub_id, @_);
                        };
                        # TODO: ensure this cleans up on the other side when it is destroyed
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
            print "$RMI::DEBUG_INDENT N: $$ - made proxy for $value\n" if $RMI::DEBUG;
        }
        elsif ($type == 2) {
            # was a proxy on the other side: get the real object
            my $o = $sent_objects->{$value};
            print "$RMI::DEBUG_INDENT N: $$ reconstituting local object $value, but not found in my sent objects!\n" and die unless $o;
            push @unserialized, $o;
            print "$RMI::DEBUG_INDENT N: $$ - resolved local object for $value\n" if $RMI::DEBUG;
        }
    }
    print "$RMI::DEBUG_INDENT N: $$ remote side destroyed: @$received_and_destroyed_ids\n" if $RMI::DEBUG;
    my @done = grep { defined $_ } delete @$sent_objects{@$received_and_destroyed_ids};
    unless (@done == @$received_and_destroyed_ids) {
        print "Some IDS not found in the sent list: done: @done, expected: @$received_and_destroyed_ids\n";
        
    }
    return @unserialized;    
}

# this wraps Perl eval($src) in a method so that it can be called from the remote side
# it allows requests for remote eval to be re-written as a static method call

sub _eval {
    my $src = $_[0];
    my @result = eval $src;
    die $@ if $@;
    return @result;
}

# this is used when a CODE ref is proxied, since you can't tie CODE refs..

sub _exec_coderef_for_id {
    my $sub_id = shift;
    my $sub = $RMI::Node::executing_nodes[-1]{_sent_objects}{$sub_id};
    die "$sub is not a CODE ref.  came from $sub_id\n" unless $sub and ref($sub) eq 'CODE';
    goto $sub;
}

# basic accessors

*mk_ro_accessors = \&_mk_ro_accessors;

sub _mk_ro_accessors {
    no strict 'refs';
    my $class = caller();
    for my $p (@_) {
        my $pname = $p;
        *{$class . '::' . $pname} = sub { die "$pname is read-only!" if @_ > 1; $_[0]->{$pname} };
    }
    no warnings;
    push @{ $class . '::properties'}, @_;
}

# this proxies an entire class instead of just a single object

our %proxied_classes;

sub _implement_class_locally_to_proxy {
    my ($self,$class,$module) = @_;
    no strict 'refs';
    if ($class and not $module) {
        $module = $class;
        $module =~ s/::/\//g;
        $module .= '.pm';
    }
    elsif ($module and not $class) {
        $class = $module;
        $class =~ s/\//::/g;
        $class =~ s/.pm$//; 
    }
    if ($INC{$module}) {
    #if (keys %{ $class . '::' }) {
        die "namespace $class already has contents " . Data::Dumper::Dumper(\%{ $class . '::' });
    }
    if (my $prior = $proxied_classes{$class}) {
        die "class $class has already been proxied by $prior!";
    }
    my $path = $self->remote_eval("use $class; \$INC{'$module'}");
    for my $sub (qw/AUTOLOAD DESTROY can isa/) {
        *{$class . '::' . $sub} = \&{ 'RMI::ProxyObject::' . $sub }
    }
    $proxied_classes{$class} = $self;
    $INC{$module} = -1; #$path;
    print "$class used remotely via $self.  Module $module found at $path remotely.\n" if $RMI::DEBUG;    
}

sub virtual_lib {
    my $self = shift;
    my $virtual_lib = sub {
        my $module = pop;
        $self->_implement_class_locally_to_proxy(undef,$module);
        my $sym = Symbol::gensym();
        my $done = 0;
        return $sym, sub {
            if (! $done) {
                $_ = '1;';
                $done++;
                return 1;
            }
            else {
                return 0;
            }
        };
    }
}

# used for testing

sub _remote_has_ref {
    my ($self,$obj) = @_;
    my $id = "$obj";
    my $has_sent = $self->send_request_and_receive_response(undef, "RMI::Node::_eval", 'exists $RMI::Node::executing_nodes[-1]->{_received_objects}{"' . $id . '"}');
}

sub _remote_has_sent {
    my ($self,$obj) = @_;
    my $id = "$obj";
    my $has_sent = $self->send_request_and_receive_response(undef, "RMI::Node::_eval", 'exists $RMI::Node::executing_nodes[-1]->{_sent_objects}{"' . $id . '"}');
}

1;
