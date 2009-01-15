package RMI::Node;

use strict;
use warnings;
use version;
our $VERSION = qv('0.1');

# Note: if any of these get proxied as full classes, we'd have issues.
# Since it's impossible to proxy a class which has already been "used",
# we use them at compile time...
use RMI;
use Tie::Array;
use Tie::Hash;
use Tie::Scalar;
use Tie::Handle;
use Data::Dumper;
use Scalar::Util;
use Carp;
require 'Config_heavy.pl'; 

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
    if (my $p = delete $self->{allow_packages}) {
        $self->{allow_packages} = { map { $_ => 1 } @$p };
    }
    for my $p (@RMI::Node::properties) {
        unless ($self->{$p}) {
            die "no $p on object!"
        }
    }
    return $self;
}

sub send_request_and_receive_response {
    my $self = shift;
    my $wantarray = wantarray;
    $self->_send_request($wantarray,@_);
    return $self->_receive_response($wantarray); 
}

sub _send_request {
    my ($self, $wantarray, $o, $m, @p) = @_;
    my $hout = $self->{writer};
    my $hin = $self->{reader};
    my $sent_objects = $self->{_sent_objects};
    my $received_objects = $self->{_received_objects};
    my $received_and_destroyed_ids = $self->{_received_and_destroyed_ids};
    my $os = $o || '<none>';

    print "$RMI::DEBUG_MSG_PREFIX N: $$ calling via $self on $os: $m with @p\n" if $RMI::DEBUG;

    # pacakge the call and params for transmission
    my @px = $self->_serialize($sent_objects,$received_objects,$received_and_destroyed_ids,[$o,@p]);
    my $s = Data::Dumper->new([['query',$m,$wantarray,@px]])->Terse(1)->Indent(0)->Useqq(1)->Dump;
    if ($s =~ /\n/) {
        die "found a newline in dumper output!\n$s<\n";
    }
    print "$RMI::DEBUG_MSG_PREFIX N: $$ sending $s\n" if $RMI::DEBUG;
    
    # send it
    my $r = $hout->print($s,"\n");
    unless ($r) {
        die "failed to send! $!";
    }
    return $r;    
}

sub _receive_response {
    my ($self,$wantarray) = @_;    
    for (1) {
        # this will occur once, or more than once if we get a counter-request
        my ($type, $incoming_data) = $self->_read();
        if (not defined $type) {
            die "$RMI::DEBUG_MSG_PREFIX N: $$ connection failure before result returned!";
        }
        if ($type eq 'result') {
            print "$RMI::DEBUG_MSG_PREFIX N: $$ returning @$incoming_data\n" if $RMI::DEBUG;
            my @result = $self->_deserialize($incoming_data);
            if ($wantarray) {
                return @result;
            }
            else {
                return $result[0];
            }
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
            print "$RMI::DEBUG_MSG_PREFIX N: $$ shutting down\n" if $RMI::DEBUG;
            $self->{is_closed} = 1;
            return;
        }
        if ($type eq 'query') {
            $self->_process_query($incoming_data);
            redo;
        }
        else {
            die "$RMI::DEBUG_MSG_PREFIX N: $$ recieved $type directly from client instead of query?!";
        }
    }
    return;
}

sub _read {
    my ($self) = @_;
    my $hin = $self->{reader};
    my $hout = $self->{writer};
    
    print "$RMI::DEBUG_MSG_PREFIX N: $$ receiving\n" if $RMI::DEBUG;
    Carp::confess() unless $hin;
    my $incoming_text = $hin->getline;
    if (not defined $incoming_text) {
        return;
    }

    print "$RMI::DEBUG_MSG_PREFIX N: $$ got $incoming_text" if $RMI::DEBUG;
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

# the real work is done by 4 methods, 4 object-level tracked data structures, and 2 global data structures...

# object-level data structurs
_mk_ro_accessors(qw/_sent_objects _received_objects _received_and_destroyed_ids _tied_objects_for_tied_refs/);

# required for the implementation of proxied CODE references
our @executing_nodes; 

# tracks classes which have been fully proxied in the process of the client.
our %proxied_classes;

sub _process_query {
    my ($self,$incoming_data) = @_;

    my $hin = $self->{reader};
    my $hout = $self->{writer};
    my $sent_objects = $self->{_sent_objects};
    my $received_objects = $self->{_received_objects};
    my $received_and_destroyed_ids = $self->{_received_and_destroyed_ids};
    
    no warnings;
    print "$RMI::DEBUG_MSG_PREFIX N: $$ processing (serialized): @$incoming_data\n" if $RMI::DEBUG;
    my ($m,$wantarray,@px) = @$incoming_data;
    my @p = $self->_deserialize(\@px);
    my $o = shift @p;
    print "$RMI::DEBUG_MSG_PREFIX N: $$ unserialized object $o and params: @p\n" if $RMI::DEBUG;
    my @result;
    push @executing_nodes, $self;
    eval {
        if (defined $o) {
            #eval "use $o"; if not ref($o);
            if (not defined $wantarray) {
                print "$RMI::DEBUG_MSG_PREFIX N: $$ object call with undef wantarray\n" if $RMI::DEBUG;
                $o->$m(@p);
            }
            elsif ($wantarray) {
                print "$RMI::DEBUG_MSG_PREFIX N: $$ object call with true wantarray\n" if $RMI::DEBUG;
                @result = $o->$m(@p);
            }
            else {
                print "$RMI::DEBUG_MSG_PREFIX N: $$ object call with false wantarray\n" if $RMI::DEBUG;
                my $result = $o->$m(@p);
                @result = ($result);
            }
        }
        else {
            no strict 'refs';
            if (not defined $wantarray) {
                print "$RMI::DEBUG_MSG_PREFIX N: $$ function call with undef wantarray\n" if $RMI::DEBUG;                            
                $m->(@p);
            }
            elsif ($wantarray) {
                print "$RMI::DEBUG_MSG_PREFIX N: $$ function call with true wantarray\n" if $RMI::DEBUG;                
                @result = $m->(@p);
            }
            else {
                print "$RMI::DEBUG_MSG_PREFIX N: $$ function call with false wantarray\n" if $RMI::DEBUG;                
                my $result = $m->(@p);
                @result = ($result);
            }
        }
    };
    pop @executing_nodes;
    # we MUST undef these in case they are the only references to objects which need to be destroyed
    $o = undef;
    @p = ();
    if ($@) {
        print "$RMI::DEBUG_MSG_PREFIX N: $$ executed with EXCEPTION (unserialized): $@\n" if $RMI::DEBUG;
        my @serialized = $self->_serialize($sent_objects, $received_objects, $received_and_destroyed_ids, [$@]);
        print "$RMI::DEBUG_MSG_PREFIX N: $$ EXCEPTION serialized as @serialized\n" if $RMI::DEBUG;
        my $s = Data::Dumper->new([['exception', @serialized]])->Terse(1)->Indent(0)->Useqq(1)->Dump;
        @$received_and_destroyed_ids = ();
        $s =~ s/\n/ /gms;
        $hout->print($s,"\n");                
    }
    else {
        print "$RMI::DEBUG_MSG_PREFIX N: $$ executed with result (unserialized): @result\n" if $RMI::DEBUG;
        my @serialized = $self->_serialize($sent_objects, $received_objects, $received_and_destroyed_ids, \@result);
        print "$RMI::DEBUG_MSG_PREFIX N: $$ result serialized as @serialized\n" if $RMI::DEBUG;
        my $s = Data::Dumper->new([['result', @serialized]])->Terse(1)->Indent(0)->Useqq(1)->Dump;
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
            if ($type eq "RMI::ProxyObject" or $proxied_classes{$type}) {
                my $key = $RMI::Node::remote_id_for_object{$o};
                print "$RMI::DEBUG_MSG_PREFIX N: $$ proxy $o references remote $key:\n" if $RMI::DEBUG;
                push @serialized, 2, $key;
                next;
            }
            elsif ($type eq "RMI::ProxyReference") {
                # This only happens from inside of AUTOLOAD in RMI::ProxyReference.
                # There is some other reference in the system which has been tied, and this object is its
                # surrogate.  We need to make sure that reference is deserialized on the other side.
                my $key = $RMI::Node::remote_id_for_object{$o};
                print "$RMI::DEBUG_MSG_PREFIX N: $$ tied proxy special obj $o references remote $key:\n" if $RMI::DEBUG;
                push @serialized, 2, $key;
                next;
            }            
            else {
                # TODO: use something better than stringification since this can be overridden!!!
                my $key = "$o";
                
                # TODO: handle extracting the base type for tying for regular objects which does not involve parsing
                my $base_type = substr($key,index($key,'=')+1);
                $base_type = substr($base_type,0,index($base_type,'('));
                my $code;
                if ($base_type ne $type) {
                    # blessed reference
                    $code = 1;
                    if (my $allowed = $self->{allow_packages}) {
                        unless ($allowed->{ref($o)}) {
                            die "objects of type " . ref($o) . " cannot be passed from this RMI node!";
                        }
                    }
                }
                else {
                    # regular reference
                    $code = 3;
                }
                
                push @serialized, $code, $key;
                $sent_objects->{$key} = $o;
            }
        }
        else {
            push @serialized, 0, $o;
        }
    }
    @$unserialized_values_arrayref = (); # essential to get the DESTROY handler to fire for proxies we're not holding on-to
    print "$RMI::DEBUG_MSG_PREFIX N: $$ destroyed proxies: @$received_and_destroyed_ids\n" if $RMI::DEBUG;
    return (@serialized);
}

sub _deserialize {
    my ($self, $serialized) = @_;
    my $sent_objects = $self->{_sent_objects};
    my $received_objects = $self->{_received_objects};
    my $received_and_destroyed_ids = shift @$serialized;
    my @unserialized;    
    while (@$serialized) { 
        my $type = shift @$serialized;
        my $value = shift @$serialized;
        if ($type == 0) {
            # primitive value
            print "$RMI::DEBUG_MSG_PREFIX N: $$ - primitive " . (defined($value) ? $value : "<undef>") . "\n" if $RMI::DEBUG;
            push @unserialized, $value;
        }
        elsif ($type == 1 or $type == 3) {
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
                        $self->send_request_and_receive_response(undef, 'RMI::Node::_exec_coderef_for_id', $sub_id, @_);
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
                    if ($proxied_classes{$remote_class}) {
                        bless $o, $remote_class;
                    }
                    else {
                        bless $o, 'RMI::ProxyObject';    
                    }
                }
                $received_objects->{$value} = $o;
                Scalar::Util::weaken($received_objects->{$value});
                my $o_id = "$o";
                my $t_id = "$t";
                $RMI::Node::node_for_object{$o_id} = $self;
                $RMI::Node::remote_id_for_object{$o_id} = $value;
                if ($t) {
                    # ensure calls to work with the "tie-buddy" to the reference
                    # result in using the orinigla reference on the "real" side
                    $RMI::Node::node_for_object{$t_id} = $self;
                    $RMI::Node::remote_id_for_object{$t_id} = $value;
                }
            }
            
            push @unserialized, $o;
            print "$RMI::DEBUG_MSG_PREFIX N: $$ - made proxy for $value\n" if $RMI::DEBUG;
        }
        elsif ($type == 2) {
            # exists on this side, and was a proxy on the other side: get the real reference by id
            my $o = $sent_objects->{$value};
            print "$RMI::DEBUG_MSG_PREFIX N: $$ reconstituting local object $value, but not found in my sent objects!\n" and die unless $o;
            push @unserialized, $o;
            print "$RMI::DEBUG_MSG_PREFIX N: $$ - resolved local object for $value\n" if $RMI::DEBUG;
        }
    }
    print "$RMI::DEBUG_MSG_PREFIX N: $$ remote side destroyed: @$received_and_destroyed_ids\n" if $RMI::DEBUG;
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
    if (wantarray) {
        my @result = eval $src;
        die $@ if $@;
        return @result;        
    }
    else {
        my $result = eval $src;
        die $@ if $@;
        return $result;
    }
}

sub _use {
    my $self = shift;
    my $pkg = shift;
    my @args = @_;
    eval "use $pkg;";
    die $@ if $@;
}


sub _use_lib {
    my $self = shift;
    my @args = @_;
    eval "use lib \@args;";
    die $@ if $@;
}

# this is used when a CODE ref is proxied, since you can't tie CODE refs..

sub _exec_coderef_for_id {
    my $sub_id = shift;
    my $sub = $RMI::Node::executing_nodes[-1]{_sent_objects}{$sub_id};
    die "$sub is not a CODE ref.  came from $sub_id\n" unless $sub and ref($sub) eq 'CODE';
    goto $sub;
}


# basic accessors

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

sub _bind_local_vars_to_remote {
    my $self = shift;
    my $caller = caller();
    my $full_var;
    for my $var (@_) {
        my $type = substr($var,0,1);
        if (index($var,'::')) {
            $full_var = substr($var,1);
        }
        else {
            $full_var = $caller . '::' . substr($var,1);
        }
        my $src = '\\' . $type . $full_var . ";\n";
        #print $src;
        my $r = $self->call_eval($src);
        die $@ if $@;
        #print "got $r\n";
        $src = '*' . $full_var . ' = $r' . ";\n";
        #print $src;
        eval $src;
        die $@ if $@;
    }
    return scalar(@_);
}

sub _bind_local_class_to_remote {
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
    if (my $prior = $proxied_classes{$class}) {
        if ($prior == $self) {
            die "class $class has already been proxied by this RMI client!";            
        }
        else {
            die "class $class has already been proxied by another RMI client: $prior!";
        }
    }    
    if (my $path = $INC{$module}) {
        die "module $module has already been used from path: $path";
    }
    my $path = $self->call_eval("use $class; \$INC{'$module'}");
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
        $DB::single = 1;
        my $module = pop;
        $self->_bind_local_class_to_remote(undef,$module);
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

=pod

=head1 NAME

RMI::Node - transparent proxying through IO handles

=head1 SYNOPSIS

    # make generic connected pipes for the sake of example
    pipe($client_reader, $server_writer);  
    pipe($server_reader,  $client_writer);     
    $server_writer->autoflush(1);
    $client_writer->autoflush(1);
    
    # make 2 nodes, one to act as a server, one as a client
    $c = RMI::Node->new(
        reader => $client_reader,
        writer => $client_writer,
    );
    $s = RMI::Node->new(
        writer => $server_reader,
        reader => $server_writer,
    );
    
    sub main::add { return $_[0] + $_[1] }
    
    if (fork()) {
        # service one request and exit
        $s->receive_request_and_send_response();
        exit;
    }
    
    # send one request and get the result
    $sum = $c->send_request_and_receive_response('main', 'add', 5, 6);
    
    
=head1 DESCRIPTION

This is the base class for RMI::Client and RMI::Server.  RMI::Client and RMI::Server
both implement a wrapper around the RMI::Node interface, with convenience methods
around initiating the sending or receiving of messages.

An RMI::Node object embeds the core methods for bi-directional communication.
Because the server often has to make counter requests of the client, the pair
will often switch functional roles several times in the process of servicing a
particular call. This class is not technically abstract, and is fully functional in
either the client or server role without subclassing.  Most direct coding against
this API, however, should be done by implementors of new types of clients/servers.

See B<RMI> for an overview of how clients and servers interact.  The documentation
in this module will describe the general piping system between clients and servers.

An RMI::Node requires that the reader/writer handles be explicitly specified at
construction time.  It also requires and that the code which uses it is be wise
about calling methods to send and recieve data which do not cause it to block
indefinitely. :)

=back

=head1 METHODS

=item ($result|@result) = send_request_and_recieve_response($wantarray,$object,$method,@params)

This is the primary method used by nodes acting in a client-like capacity.

 $wantarray:    1, '' or undef: the wantarray() value of the original calling code
 $object:       the object or class on which the method is being called, may be undef for subroutine calls
 $method:       the method to call on $object (even if $object is a class name), or the fully-qualified sub name
 @params:       the values which should be passed to $method
 
 $result|@result: the return value will be either a scalar or list, depending on the value of $wantarray

 This method sends a method call request through the writer, and waits on a response from the reader.
 It will handle a response with the answer, exception messages, and also handle counter-requests
 from the server, which may occur b/c the server calls methods on objects passed as parameters.

=item receive_request_and_send_response()

 This method waits for a single request to be received from its reader handle, services
 the request, and sends the results through the writer handle.
 
 It is possible that, while servicing the request, it will make counter requests, and those
 counter requests, may yield counter-counter-requests which call this method recursively.

=item virtual_lib

 This method returns an anonymous subroutine which can be used in a "use lib $mysub"
 call, to cause subsequent "use" statements to go through this node to its partner.
 
 e.x.:
    use lib RMI::Client::Tcp-new(host=>'myserver',port=>1234)->virtual_lib;
 
 
=head1 EXAMPLES

=item make generic connected pipes for the sake of example
    
    # you should really make RMI::Client and RMI::Server subclasses, but..
    
    pipe($client_reader, $server_writer);  
    pipe($server_reader,  $client_writer);     
    $server_writer->autoflush(1);
    $client_writer->autoflush(1);
    
    $c = RMI::Node->new(
        reader => $client_reader,
        writer => $client_writer,
    );
    
    $s = RMI::Node->new(
        writer => $server_reader,
        reader => $server_writer,
    );
    
    sub main::add { return $_[0] + $_[1] }
    
    if (fork()) {
        # service one request and exit
        $s->receive_request_and_send_response();
        exit;
    }
    
    # send one request and get the result
    $sum = $c->send_request_and_receive_response('main', 'add', 5, 6);

=head1 BUGS AND CAVEATS

See general bugs in B<RMI> for general system limitations

=head1 SEE ALSO

B<RMI>, B<RMI::Server>, B<RMI::Client>

B<IO::Socket>, B<Tie::Handle>, B<Tie::Array>, B<Tie:Hash>, B<Tie::Scalar>

=cut


1;
