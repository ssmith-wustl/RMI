require 'rmi'
require 'rmi/proxywrapper'

class RMI::ProxyWrapper::Proc < Proc
    include RMI::ProxyWrapper

    def initialize(delegate, &block) 
        @delegate = delegate
        super(delegate) do 
            print "CALLING DUMMY BLOCK!\n"
        end
    end

    def call(a,b)
        @delegate.call(a,b)
    end

    def arity(*a)
        print "call arity on #{self} with delegate #{@delegate} with params #{a}\n"
        @delegate.arity(*a)
    end

    methods = Proc.methods - Object.methods

    methods.each do |name|
        src = <<EOS
            def #{name} (*args)
                print "call #{args}\n"
                @delegate.send(:#{name}, *args)
            end
EOS
    end

end

