require "testclass"

class RMI::TestClass1 < RMI::TestClass
    def m1
        return @pid
    end

    def m2(v)
        return(v*2)
    end

    def m3(other)
        other.m1
    end

    def m4(other1, other2)
        p1 = other1.m1
        p2 = other2.m1
        p3 = other1.m3(other2)
        return "#{p1}.#{p2}.#{p3}"
    end

    def dummy_accessor(*args)
        if args.length > 0
            @m5 = args[0]
        end
        return @m5
    end
end
