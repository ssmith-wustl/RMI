require 'rmi'
require 'rmi/proxywrapper'

class RMI::ProxyWrapper::Proc < Proc
    include RMI::ProxyWrapper

    def initialize(delegate, &block) 
        super(delegate) do 
            print "CALLING DUMMY BLOCK!\n"
        end
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

