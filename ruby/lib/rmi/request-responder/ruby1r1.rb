require 'rmi'

class RMI::RequestResponder::Ruby1r1 < RMI::RequestResponder

@@executing_nodes = [] # required for some methods on the remote side to find the RMI node acting upon them
@@proxied_classes = {} # tracks classes which have been fully proxied into this process by some client

# used by the requestor to capture context
def _capture_context 
    return 1 
end

# used by the requestor to use that context after a result is returned
def _return_result_in_context(response_data, context) 
    $RMI_DEBUG && print("#{$RMI_DEBUG_MSG_PREFIX} N: #{$$} returning #{response_data} w/o context consideration\n")
    return response_data[0]
end

# used by the responder to process the message data, with embedded context
def _process_request_in_context_and_return_response(message_data) 
    call_type = message_data.shift

    # Ruby does not do context-specific returns (like languages like Perl do)
    context = message_data.shift
  
    $RMI_DEBUG && print("#{$RMI_DEBUG_MSG_PREFIX} N: #{$$} processing request #{call_type} with : #{message_data}\n")
    
    # swap call_ for _respond_to_
    method = '_respond_to_' + call_type[5..-1]
   
    $RMI_DEBUG && print("#{$RMI_DEBUG_MSG_PREFIX} N: #{$$} method is #{method} with params #{message_data} count #{message_data.length}\n")
    
    result = nil
    exception = nil
    @@executing_nodes.push @node
    begin
        $RMI_DEBUG && print("#{$RMI_DEBUG_MSG_PREFIX} N: #{$$} object call with undef wantarray\n")
        result = self.send(method, *message_data)
    rescue Exception => e 
        exception = e
    end
    @@executing_nodes.pop

    # we MUST undef these in case they are the only references to remote objects which need to be destroyed
    # the DESTROY handler will queue them for deletion, and _send() will include them in the message to the other side
    message_data.clear
    
    if (exception)
        $RMI_DEBUG && print("#{$RMI_DEBUG_MSG_PREFIX} N: #{$$} executed with EXCEPTION (unserialized): #{exception}\n")
        return 'exception', [exception] 
    else 
        $RMI_DEBUG && print("#{$RMI_DEBUG_MSG_PREFIX} N: #{$$} executed with result (unserialized): #{result}\n")
        return 'result', [result]
    end
end

def _resolve_namespace(text)
    words = text.split('::')
    ns = Object
    while (words.length > 0) 
        next_ns = ns.const_get(words[0])
        if next_ns == nil
            raise IOError, "no #{words[0]} in #{ns}\n"
        end
        ns = next_ns
        words.shift()
    end
    return ns
end

##

def call_eval(src,*params) 
    return @node.send_request_and_receive_response('call_eval', '', '', src, *params);    
end

def _respond_to_eval(dummy_no_class, dummy_no_method, src, *args)
    result = eval src
    return result
end

##

def call_function(fname,*params)
    (namespace, name) = /^(.*)::([^\:]*)$/.match(fname)[1,2]
    return @node.send_request_and_receive_response('call_function', namespace, name, *params);
end

def _respond_to_function(pkg, sub, *params)
    ns = _resolve_namespace(pkg)
    m = ns.method(sub)
    return m.call(*params)
end

##

def call_class_method(klass, method, *params)
    return @node.send_request_and_receive_response('call_class_method', klass, method, *params);
end

def _respond_to_class_method(klass, method, *params)
    ns = _resolve_namespace(klass)
    m = ns.method(method)
    return m.call(*params)
end

##

def call_object_method(obj,method,*params)
    #my $class = ref($object);
    #$class =~ s/RMI::Proxy:://;
    return @node.send_request_and_receive_response('call_object_method', @@class, method, obj, *params);
end

def _respond_to_object_method(klass, method, obj, params) 
    object.send(method, *params)
end


##

=begin



sub call_use {
    my ($self,$class,$module,$use_args) = @_;

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

    my @exported;
    my $path;
    ($class,$module,$path, @exported) = 
        $self->send_request_and_receive_response(
            'call_use',
            $class,
            '',
            $module,
            defined($use_args),
            ($use_args ? @$use_args : ())
        );
        
    return ($class,$module,$path,@exported);
}

def _respond_to_use
    (self,class,dummy_no_method,module,has_args,use_args) = _

    no strict 'refs'
    if (class and not module)
        module = class
        module =~ s/::/\//g
        module .= '.pm'
    }
    elsif (module and not class)
        class = module
        class =~ s/\//::/g
        class =~ s/.pm// 
    }
    
    n = RMI::Exported::count++
    tmp_module_to_catch_exports = 'RMI::Exported::P' + n
    my $src = "
        module tmp_module_to_catch_exports
        require class
        \exports = ()
        if (\has_args)
            if (\@use_args)
                class.import(\use_args)
                \exports = grep { {tmp_module_to_catch_exports}.can(\_) } keys \%{tmp_module_to_catch_exports}::
            }
            else 
                # print qq/no import because of empty list!/
            }
        }
        else 
            class.import()
            \exports = grep { {tmp_module_to_catch_exports}.can(\_) } keys \%{tmp_module_to_catch_exports}::
        }
        return (\INC{'module'}, \exports)
    "
    (path, exported) = eval(src)
    die  if 
    return (class,module,path,exported)
end

sub call_use_lib {
    my ($self,$lib, @other) = @_;
    return $self->send_request_and_receive_response('call_use_lib', '', '', $lib);
}

def _respond_to_use_lib
    self = shift
    dummy_no_class = shift
    dummy_no_method = shift
    libs = _
    require lib
    return lib.import(libs)
end

sub use_lib_remote {
    my $self = shift;
    unshift @INC, $self->virtual_lib;
}

sub virtual_lib {
    my $self = shift;
    my $virtual_lib = sub {
        my $module = pop;
        $self->bind_local_class_to_remote(undef,$module);
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

sub bind {
    my $self = shift;
    if (substr($_[0],0,1) =~ /\w/) {
        $self->bind_local_class_to_remote(@_);
    }
    else {
        $self->bind_local_var_to_remote(@_);
    }
}

sub use_remote {
    my $self = shift;
    my $class = shift;
    $self->bind_local_class_to_remote($class, undef, @_);
    $self->bind_local_var_to_remote('@' . $class . '::ISA');
    return 1;
}

def _respond_to_coderef
    # This is used when a CODE ref is proxied, since you can't tie CODE refs.
    # It does not have a matching caller in RMI::Client.
    # The other reference types are handled by "tie" to RMI::ProxyReferecnce.

    # NOTE: It's important to shift these two parameters off since goto must 
    # pass the remainder of @_ to the subroutine.
    self = shift
    dummy_no_class = shift
    dummy_no_method = shift
    sub_id = shift
    node = node
    sub = node.{_sent_objects}{sub_id}
    Carp::confess("no coderef sub_id in the list of sent CODE refs, but a proxy thinks it has this value?") unless sub
    die "sub is not a CODE ref.  came from sub_id\n" unless sub and ref(sub) eq 'CODE'
    goto sub
end

# BASIC API -- implemented by all protocols --

def bind_local_var_to_remote
    # this proxies a single variable

    self = shift
    node = node
    
    local_var = shift
    remote_var = (_ ? :.shift local_var)
    
    type = substr(local_var,0,1)
    if (index(local_var,'::'))
        local_var = substr(local_var,1)
    }
    else 
        caller = caller()
        local_var = caller + '::' + substr(local_var,1)
    }

    unless (type == substr(remote_var,0,1))
        die "type mismatch: local var local_var has type type, while remote is remote_var!"
    }
    if (index(remote_var,'::'))
        remote_var = substr(remote_var,1)
    }
    else 
        caller = caller()
        remote_var = caller + '::' + substr(remote_var,1)
    }
    
    src = '\\' + type + remote_var + "\n";
    r = node.call_eval(src)
    die  if 
    src = '*' + local_var + ' = r' + "\n";
    eval src
    die  if 
    return 1
end


def bind_local_class_to_remote
    # this proxies an entire class instead of just a single object
    
    self = shift
    node = node
    
    (class,module,path,exported) = node.call_use(_)
    re_bind = 0
    if (my prior = RMI::proxied_classes{class})
        if (prior != node)
            die "class class has already been proxied by another RMI client: prior!"
        }
        else 
            # re-binding a class to the same remote side doesn't hurt,
            # and allowing it allows the effect of export to occur
            # in multiple places on the client side.
        }
    }
    elsif (my path = INC{module})
        die "module module has already been used locally from path: path"
    }
    no strict 'refs'
    for my $sub (qw/AUTOLOAD DESTROY can isa/) {
        *{$class . '::' . $sub} = \&{ 'RMI::ProxyObject::' . $sub }
    }
    if (@exported)
        caller ||= caller(0)
        if (substr(caller,0,5) == 'RMI::') caller = caller(2) }  # change this num as we move this method
        for my $sub (@exported) {
            pair = ('&' + caller + '::' + sub => '&' + class + '::' + sub)
            #{RMI_DEBUG} && print("$RMI_DEBUG_MSG_PREFIX N: #{$$} bind pair $pair[0] $pair[1]\n")
            self.bind_local_var_to_remote(pair)
        }
    }
    RMI::proxied_classes{class} = node
    INC{module} = node
    #{RMI_DEBUG} && print("$class used remotely via $self ($node).  Module $module found at $path remotely.\n")    
end


# for cases where we really do want to transfer the original data...

def _create_remote_copy
    (self,v) = _
    serialized = '  ' + Data::Dumper.new([v]).Terse(1).Indent(0).Useqq(1).Dump()
    proxy = node.send_request_and_receive_response('call_eval','','',serialized)
    return proxy
end

def _create_local_copy
    (self,v) = _
    serialized = node.send_request_and_receive_response('call_eval','','','Data::Dumper::Dumper(_[0])',v)
    local = eval('  ' + serialized)
    die 'Failed to serialize!: ' +  if 
    return local    
end

# interrogate the remote side
# TODO: this should be part of the node API and accessing the remote node should provide an answer

def _is_proxy
    (self,obj) = _
    node = node
    node.send_request_and_receive_response('call_eval', '', '', 'id = "_[0]" r = exists RMI::executing_nodes[-1].{_sent_objects}{id}; return r', obj);
end

def _has_proxy
    (self,obj) = _
    id = "obj"
    node.send_request_and_receive_response('call_eval', '', '', 'exists RMI::executing_nodes[-1].{_received_objects}{"' + id + '"}')
end

def _remote_node
    (self) = _
    node.send_request_and_receive_response('call_eval', '', '', 'RMI::executing_nodes[-1]')
end

1

=pod

=head1 NAME

RMI::RequestResponder::Perl5r1

=head1 VERSION

This document describes RMI::RequestResponder::Perl5r1 for RMI v0.11.

=head1 DESCRIPTION

The RMI::RequestResponder::Perl5r1 module handles responding to requests in the
perl5r1 request protocol format.


=head1 SEE ALSO

B<RMI>, B<RMI::Node>

=head1 AUTHORS

Scott Smith <sakoht@cpan.org>

=head1 COPYRIGHT

Copyright (c) 2008 - 2010 Scott Smith <sakoht@cpan.org>  All rights reserved.

=head1 LICENSE

This program is free software you can redistribute it and/or modify it under
the same terms as Perl itself.

The full text of the license can be found in the LICENSE file included with this
module.

=cut
=end

end

