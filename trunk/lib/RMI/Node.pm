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

our @executing_nodes; # required for some methods on the remote side to find the RMI node acting upon them
our %proxied_classes; # tracks classes which have been fully proxied in the process of the client.

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
    my ($self, $object, $method, @params) = @_;
    my $wantarray = wantarray;

    if ($RMI::DEBUG) {
        print "$RMI::DEBUG_MSG_PREFIX N: $$ calling via $self on $object: $method with @params\n";
    }
    
    unless ($self->_send('query',[$object,@params],[$method,$wantarray])) {
        die "failed to send! $!";
    }

    my ($type, @result);
    while(1) {
        ($type, @result) = $self->_receive();
        last if ($type eq 'result');
        return if ($type eq 'close');
        if ($type eq 'query') {
            $self->_send(@result);
            redo;
        }
    }
    
    if ($wantarray) {
        print "$RMI::DEBUG_MSG_PREFIX N: $$ returning list @result\n" if $RMI::DEBUG;
        return @result;
    }
    else {
        print "$RMI::DEBUG_MSG_PREFIX N: $$ returning scalar $result[0]\n" if $RMI::DEBUG;
        return $result[0];
    }
}

sub receive_request_and_send_response {
    my ($self) = @_;
    my ($type, @data) = $self->_receive();
    if ($type eq 'close') {
        return;
    }
    elsif ($type eq 'query') {
        $self->_send(@data);
        return 1;
    }
    else {
        die "Unexpected message type $type!  Data was:" . Data::Dumper::Dumper(\@data);
    }        
}

# private API

_mk_ro_accessors(qw/_sent_objects _received_objects _received_and_destroyed_ids _tied_objects_for_tied_refs/);

sub _send {
    my ($self, $type, $proxyables, $primitives) = @_;
    my $s = $self->_serialize($type,$proxyables,$primitives);    
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
    
    my $incoming_data = eval "no strict; no warnings; $incoming_text";
    if ($@) {
        die "Exception de-serializing message: $@";
    }        

    my $type = shift @$incoming_data;
    if (! defined $type) {
        die "unexpected undef type from incoming message:" . Data::Dumper::Dumper($incoming_data);
    }    

    do {
        no warnings;    
        print "$RMI::DEBUG_MSG_PREFIX N: $$ processing (serialized): @$incoming_data\n" if $RMI::DEBUG;
    };
    
    my @deserialized = $self->_deserialize($type,$incoming_data);
    
    if ($type eq 'query') {
        my ($method,$wantarray,$object,@params) = @deserialized;
        my ($return_type, $return_value_arrayref) = $self->_process_query($object,$method,\@params,$wantarray);
        
        # we MUST undef these in case they are the only references to remote objects which need to be destroyed
        # the DESTROY handler will queue them for deletion, and _send() will include them in the message to the other side
        $object = undef;
        @params = ();
        
        return ('query', $return_type, $return_value_arrayref);
    }
    elsif ($type eq 'result') {
        return ('result', @deserialized);
    }
    elsif ($type eq 'exception') {
        die $deserialized[0];
    }
    else {
        die "unexpected message type from RMI message: $type";
    }
    
}

sub _process_query {
    my ($self,$object,$method,$params,$wantarray) = @_;

    do {    
        no warnings;
        print "$RMI::DEBUG_MSG_PREFIX N: $$ unserialized object $object and params: @$params\n" if $RMI::DEBUG;
    };
    
    push @executing_nodes, $self;
    
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
    
    pop @executing_nodes;
    
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
    my ($self,$mtype,$proxyables,$primitives) = @_;    
    
    my $sent_objects = $self->{_sent_objects};
    my $received_and_destroyed_ids = $self->{_received_and_destroyed_ids};

    my @serialized = ([@$received_and_destroyed_ids]);
    @$received_and_destroyed_ids = ();
    
    for my $o (@$proxyables) {
        if (my $type = ref($o)) {
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
    @$proxyables = (); # essential to get the DESTROY handler to fire for proxies we're not holding on-to
    print "$RMI::DEBUG_MSG_PREFIX N: $$ destroyed proxies: @$received_and_destroyed_ids\n" if $RMI::DEBUG;
    
    print "$RMI::DEBUG_MSG_PREFIX N: $$ $mtype serialized as @serialized\n" if $RMI::DEBUG;
    my $s = Data::Dumper->new([[$mtype, ($mtype eq 'query' ? @$primitives : ()), @serialized]])->Terse(1)->Indent(0)->Useqq(1)->Dump;
    if ($s =~ s/\n/ /gms) {
        die "newline found in message data!";
    }
    
    return $s;
}

# deserialize params when receiving a query, or results when receiving a response
sub _deserialize {
    my ($self,$mtype,$serialized) = @_;

    my @unserialized;
    if ($mtype eq 'query') {
        push @unserialized, shift @$serialized; # method
        push @unserialized, shift @$serialized; # wantarray
    }   

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
                        $self->send_request_and_receive_response(undef, 'RMI::Node::_receive_exec_codref', $sub_id, @_);
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
    return @unserialized;    
}

# MESSAGING METHODS

# this wraps Perl eval($src) in a method so that it can be called from the remote side
# it allows requests for remote eval to be re-written as a static method call

sub _call_eval {
    my ($self,$src,@params) = @_;
    return $self->send_request_and_receive_response(undef, 'RMI::Node::_receive_eval', $src, @params);    
}

sub _receive_eval {
    my $src = shift;
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

# this is used when a CODE ref is proxied, since you can't tie CODE refs..

sub _receive_exec_codref {
    my $sub_id = shift;
    my $sub = $RMI::Node::executing_nodes[-1]{_sent_objects}{$sub_id};
    die "$sub is not a CODE ref.  came from $sub_id\n" unless $sub and ref($sub) eq 'CODE';
    goto $sub;
}

# attempts to do 'use lib' remotely

sub _call_use_lib {
    my $self = shift;
    my $lib = shift;
    return $self->send_request_and_receive_response(undef, 'RMI::Node::_receive_use_lib', $lib);
}

sub _receive_use_lib {
    my $self = $RMI::Node::executing_nodes[-1];
    my $lib = shift;
    require lib;
    return lib->import($lib);
}

# attempts to use/require modules remotely

sub _call_use {
    my $self = shift;
    my $class = shift;
    my $module = shift;
    my $use_args = shift;

    my @exported;
    my $path;
    
    ($class,$module,$path, @exported) = $self->send_request_and_receive_response(undef, 'RMI::Node::_receive_use', $class,$module, defined($use_args), @$use_args);
    return ($class,$module,$path,@exported);
}

sub _receive_use {
    my $self = $RMI::Node::executing_nodes[-1];
    my ($class,$module,$has_args,@use_args) = @_;
    
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
    #print "using $class/$module with args " . Data::Dumper::Dumper($has_args);
    
    my $n = $RMI::Exported::count++;
    my $tmp_package_to_catch_exports = 'RMI::Exported::P' . $n;
    my $src = "
        package $tmp_package_to_catch_exports;
        require $class;
        my \@exports = ();
        if (\$has_args) {
            if (\@use_args) {
                $class->import(\@use_args);
                \@exports = grep { ${tmp_package_to_catch_exports}->can(\$_) } keys \%${tmp_package_to_catch_exports}::;
            }
            else {
                # print qq/no import because of empty list!/;
            }
        }
        else {
            $class->import();
            \@exports = grep { ${tmp_package_to_catch_exports}->can(\$_) } keys \%${tmp_package_to_catch_exports}::;
        }
        return (\$INC{'$module'}, \@exports);
    ";
    #print "eval with params!  count: " . scalar(@use_args) . " values: @use_args\n" if $has_args;
    #print $src;
    my ($path, @exported) = eval($src);
    die $@ if $@;
    #print "got " . Data::Dumper::Dumper($path,\@exported);
    return ($class,$module,$path,@exported);
}


# this proxies a single variable

sub _bind_local_var_to_remote {
    my $self = shift;
    my $local_var = shift;
    my $remote_var = (@_ ? shift : $local_var);
    
    my $type = substr($local_var,0,1);
    if (index($local_var,'::')) {
        $local_var = substr($local_var,1);
    }
    else {
        my $caller = caller();
        $local_var = $caller . '::' . substr($local_var,1);
    }

    unless ($type eq substr($remote_var,0,1)) {
        die "type mismatch: local var $local_var has type $type, while remote is $remote_var!";
    }
    if (index($remote_var,'::')) {
        $remote_var = substr($remote_var,1);
    }
    else {
        my $caller = caller();
        $remote_var = $caller . '::' . substr($remote_var,1);
    }
    
    my $src = '\\' . $type . $remote_var . ";\n";
    my $r = $self->call_eval($src);
    die $@ if $@;
    $src = '*' . $local_var . ' = $r' . ";\n";
    eval $src;
    die $@ if $@;
    return 1;
}

# this proxies an entire class instead of just a single object

sub _bind_local_class_to_remote {
    my $self = shift;
    my ($class,$module,$path,@exported) = $self->_call_use(@_);
    my $re_bind = 0;
    if (my $prior = $proxied_classes{$class}) {
        if ($prior != $self) {
            die "class $class has already been proxied by another RMI client: $prior!";
        }
        else {
            # re-binding a class to the same remote side doesn't hurt,
            # and allowing it allows the effect of export to occur
            # in multiple places on the client side.
        }
    }
    elsif (my $path = $INC{$module}) {
        die "module $module has already been used locally from path: $path";
    }
    no strict 'refs';
    for my $sub (qw/AUTOLOAD DESTROY can isa/) {
        *{$class . '::' . $sub} = \&{ 'RMI::ProxyObject::' . $sub }
    }
    if (@exported) {
        my $caller ||= caller(0);
        if (substr($caller,0,5) eq 'RMI::') { $caller = caller(1) }
        for my $sub (@exported) {
            my @pair = ('&' . $caller . '::' . $sub => '&' . $class . '::' . $sub);
            print "$RMI::DEBUG_MSG_PREFIX N: $$ bind pair $pair[0] $pair[1]\n" if $RMI::DEBUG;
            $self->_bind_local_var_to_remote(@pair);
        }
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
    my $has_sent = $self->send_request_and_receive_response(undef, "RMI::Node::_receive_eval", 'exists $RMI::Node::executing_nodes[-1]->{_received_objects}{"' . $id . '"}');
}

sub _remote_has_sent {
    my ($self,$obj) = @_;
    my $id = "$obj";
    my $has_sent = $self->send_request_and_receive_response(undef, "RMI::Node::_receive_eval", 'exists $RMI::Node::executing_nodes[-1]->{_sent_objects}{"' . $id . '"}');
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

