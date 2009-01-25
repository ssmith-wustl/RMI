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
        reader => undef,
        writer => undef,
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
        unless (exists $self->{$p}) {
            die "no $p on object!"
        }
    }
    return $self;
}

sub close {
    my $self = $_[0];
    $self->{writer}->close unless $self->{reader} == $self->{writer};
    $self->{reader}->close;
}

sub send_request_and_receive_response {
    my ($self, $call_type, $object, $method, $params, $opts) = @_;
    my $wantarray = wantarray;

    if ($RMI::DEBUG) {
        print "$RMI::DEBUG_MSG_PREFIX N: $$ calling via $self on $object: $method with @$params\n";
    }
    
    $self->_send('query',[$method,$wantarray,$object,($params ? @$params : ())])
        or die "failed to send! $!";
    
    for (1) {
        my ($message_type, @message_data) = $self->_receive();
        
        if ($message_type eq 'result') {
            if ($wantarray) {
                print "$RMI::DEBUG_MSG_PREFIX N: $$ returning list @message_data\n" if $RMI::DEBUG;
                return @message_data;
            }
            else {
                print "$RMI::DEBUG_MSG_PREFIX N: $$ returning scalar $message_data[0]\n" if $RMI::DEBUG;
                return $message_data[0];
            }
        }
        elsif ($message_type eq 'close') {
            return;
        }
        elsif ($message_type eq 'query') {
            my ($return_type, $return_value_arrayref) = $self->_process_query(@message_data);
            
            # we MUST undef these in case they are the only references to remote objects which need to be destroyed
            # the DESTROY handler will queue them for deletion, and _send() will include them in the message to the other side
            @message_data = ();
            
            $self->_send($return_type, $return_value_arrayref);
            redo;
        }
        elsif ($message_type eq 'exception') {
            die $message_data[0];
        }
        else {
            die "unexpected message type from RMI message: $message_type";
        }
    }    
}

sub receive_request_and_send_response {
    my ($self) = @_;
    my ($message_type, @message_data) = $self->_receive();
    
    if ($message_type eq 'query') {
        my ($return_type, $return_value_arrayref) = $self->_process_query(@message_data);
        
        # We MUST undef these before sending results.  The send procedure will tally all objects we no longer
        # reference and update the remote side.  Without cutting our references here, actual garbage collection
        # will lag behind on the remote side until the NEXT call (see test case 01).
        @message_data = ();
        
        $self->_send($return_type, $return_value_arrayref);
        return 1;
    }
    elsif ($message_type eq 'close') {
        return;
    }
    else {
        die "Unexpected message type $message_type!  message_data was:" . message_data::Dumper::Dumper(\@message_data);
    }        
}

# private API

_mk_ro_accessors(qw/_sent_objects _received_objects _received_and_destroyed_ids _tied_objects_for_tied_refs/);

sub _send {
    my ($self, $message_type, $proxyables) = @_;
    die if @_ > 3;
    my $s = $self->_serialize($message_type,$proxyables);    
    return $self->{writer}->print($s,"\n");                
}

sub _receive {
    my ($self) = @_;
    print "$RMI::DEBUG_MSG_PREFIX N: $$ receiving\n" if $RMI::DEBUG;

    my $incoming_text = $self->{reader}->getline;
    if (not defined $incoming_text) {
        print "$RMI::DEBUG_MSG_PREFIX N: $$ connection closed\n" if $RMI::DEBUG;
        $self->{is_closed} = 1;
        return ('close');
    }
    print "$RMI::DEBUG_MSG_PREFIX N: $$ got $incoming_text" if $RMI::DEBUG;
    print "\n" if $RMI::DEBUG and not defined $incoming_text;
    
    return $self->_deserialize($incoming_text);
}

sub _process_query {
    my ($self,$method,$wantarray,$object,@params) = @_;
    my $params = \@params;
    
    do {    
        no warnings;
        print "$RMI::DEBUG_MSG_PREFIX N: $$ unserialized object $object and params: @$params\n" if $RMI::DEBUG;
    };
    
    push @RMI::executing_nodes, $self;
    
    my @result;
    eval {
        if (defined $object) {
            #eval "use $object"; if not ref($object);
            if (not defined $wantarray) {
                print "$RMI::DEBUG_MSG_PREFIX N: $$ object call with undef wantarray\n" if $RMI::DEBUG;
                $object->$method(@$params);
            }
            elsif ($wantarray) {
                print "$RMI::DEBUG_MSG_PREFIX N: $$ object call with true wantarray\n" if $RMI::DEBUG;
                @result = $object->$method(@$params);
            }
            else {
                print "$RMI::DEBUG_MSG_PREFIX N: $$ object call with false wantarray\n" if $RMI::DEBUG;
                my $result = $object->$method(@$params);
                @result = ($result);
            }
        }
        else {
            no strict 'refs';
            if (not defined $wantarray) {
                print "$RMI::DEBUG_MSG_PREFIX N: $$ function call with undef wantarray\n" if $RMI::DEBUG;                            
                $method->(@$params);
            }
            elsif ($wantarray) {
                print "$RMI::DEBUG_MSG_PREFIX N: $$ function call with true wantarray\n" if $RMI::DEBUG;                
                @result = $method->(@$params);
            }
            else {
                print "$RMI::DEBUG_MSG_PREFIX N: $$ function call with false wantarray\n" if $RMI::DEBUG;                
                my $result = $method->(@$params);
                @result = ($result);
            }
        }
    };
    
    pop @RMI::executing_nodes;
    
    if ($@) {
        print "$RMI::DEBUG_MSG_PREFIX N: $$ executed with EXCEPTION (unserialized): $@\n" if $RMI::DEBUG;
        return('exception',[$@]);
    }
    else {
        print "$RMI::DEBUG_MSG_PREFIX N: $$ executed with result (unserialized): @result\n" if $RMI::DEBUG;
        return ('result',\@result);
    }    
}

# serialize params when sending a query, or results when sending a response
sub _serialize {
    my ($self,$mtype,$proxyables) = @_;    
    
    my $sent_objects = $self->{_sent_objects};
    my $received_and_destroyed_ids = $self->{_received_and_destroyed_ids};

    my @serialized = ([@$received_and_destroyed_ids]);
    @$received_and_destroyed_ids = ();
    
    Carp::confess() unless ref($proxyables);
    for my $o (@$proxyables) {
        if (my $type = ref($o)) {
            if ($type eq "RMI::ProxyObject" or $RMI::proxied_classes{$type}) {
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
    @$proxyables = (); # essential to get the DESTROY handler to fire for proxies we're not holding on-to
    print "$RMI::DEBUG_MSG_PREFIX N: $$ destroyed proxies: @$received_and_destroyed_ids\n" if $RMI::DEBUG;
    
    print "$RMI::DEBUG_MSG_PREFIX N: $$ $mtype serialized as @serialized\n" if $RMI::DEBUG;
    my $s = Data::Dumper->new([[$mtype, @serialized]])->Terse(1)->Indent(0)->Useqq(1)->Dump;
    if ($s =~ s/\n/ /gms) {
        die "newline found in message data!";
    }
    
    return $s;
}

# deserialize params when receiving a query, or results when receiving a response
sub _deserialize {
    my ($self, $incoming_text) = @_;
    
    my $serialized = eval "no strict; no warnings; $incoming_text";
    if ($@) {
        die "Exception de-serializing message: $@";
    }        

    my $mtype = shift @$serialized;
    if (! defined $mtype) {
        die "unexpected undef type from incoming message:" . Data::Dumper::Dumper($serialized);
    }    

    do {
        no warnings;    
        print "$RMI::DEBUG_MSG_PREFIX N: $$ processing (serialized): @$serialized\n" if $RMI::DEBUG;
    };
    
    my @unserialized;

    my $sent_objects = $self->{_sent_objects};
    my $received_objects = $self->{_received_objects};
    my $received_and_destroyed_ids = shift @$serialized;
    
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
                        $self->send_request_and_receive_response('call_coderef', undef, 'RMI::Node::_exec_coderef', [$sub_id, @_]);
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
                        bless $o, 'RMI::ProxyObject';    
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

    return ($mtype,@unserialized);
}

# This is used when a CODE ref is proxied, since you can't tie CODE refs.
# it is in this class instead of the server, a coderef could be sent to the
# server, causing the server to counter-query the client.

sub _exec_coderef {
    my $sub_id = shift;
    my $sub = $RMI::executing_nodes[-1]{_sent_objects}{$sub_id};
    die "$sub is not a CODE ref.  came from $sub_id\n" unless $sub and ref($sub) eq 'CODE';
    goto $sub;
}


# used for testing

sub _remote_has_ref {
    my ($self,$obj) = @_;
    my $id = "$obj";
    my $has_sent = $self->send_request_and_receive_response('call_eval', undef, "RMI::Server::_receive_eval", ['exists $RMI::executing_nodes[-1]->{_received_objects}{"' . $id . '"}']);
}

sub _remote_has_sent {
    my ($self,$obj) = @_;
    my $id = "$obj";
    my $has_sent = $self->send_request_and_receive_response('call_eval', undef, "RMI::Server::_receive_eval", ['exists $RMI::executing_nodes[-1]->{_sent_objects}{"' . $id . '"}']);
}

# this generate basic accessors w/o using any other Perl modules which might have proxy effects

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


=pod

=head1 NAME

RMI::Node - base class for transparent proxying through IO handles

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

