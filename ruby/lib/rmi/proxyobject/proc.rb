require 'rmi'
require 'rmi/proxymethods'

class RMI::ProxyObject::Proc < Proc
    include RMI::ProxyMethods

    def call(*args)
        print "call #{args}\n"
        method_missing(:call, *args)
    end
    
    def method_missing(name, *p, &block)
        #print "MM: #{name}\n"
        $RMI_DEBUG && print("#{$RMI_DEBUG_MSG_PREFIX} #{$$} object method #{name.to_s} invoked on class #{@class} instance #{self} with params #{p} redirecting to node #{@node}\n")
        @node.send_request_and_receive_response('call_object_method', @class, name.to_s, self, *p, &block)        
    end
end

