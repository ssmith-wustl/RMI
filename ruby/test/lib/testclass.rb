class RMI::TestClass
    # abstract base class

    @@obj_this_process = {}

    @@finalizer = Proc.new do |id|
        @@obj_this_process.delete(id)
    end

    def initialize(p = {}) 
        p.each { |name,value|
            if self.respond_to? name 
                self.instance_variable_set('@' + name.to_s,value)
            else
                raise ArgumentError, 'bad parameter ' + name.to_s
            end
        }
        @@obj_this_process[self.__id__] = WeakRef.new(self)
    end

end

