require 'rmi'

module RMI::ProxyWrapper
    def initialize(delegate) 
        @delegate = delegate
    end

    def method_missing(name, *p, &block)
        @delegate.send(name, *p, &block)
    end
end

