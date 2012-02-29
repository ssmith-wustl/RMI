
require "rmi"
require "testclass"

class RMI::TestClass2 < RMI::TestClass

    @@last_arrayref = nil
    @@last_hashref = nil

    def create_and_return_arrayref(*args)
        a = [*args]
        @@last_arrayref = WeakRef.new(a)
        return a
    end

    def last_arrayref
        return @@last_arrayref    
    end

    def last_arrayref_as_string
        @@last_arrayref.join(':')
    end

    def create_and_return_hashref(params = {})
        @@last_hashref = WeakRef.new(params)
        return params 
    end

    def last_hashref_as_string
        @@last_hashref.to_s 
    end

=begin

def create_and_return_scalarref(s)
    r = last_scalarref = \s
    Scalar::Util::weaken(last_scalarref)
    return r
end

def last_scalarref_as_string
    self = shift
    return {last_scalarref}
end

def create_and_return_coderef
    self = shift
    src = shift
    sub = eval src
    die "bad source: src\n\n" if 
    die "source did not return a CODE ref: src" unless ref(sub) eq 'CODE'
    last_coderef = sub
    Scalar::Util::weaken(last_coderef)
    return sub
end

def call_my_sub
    self = shift
    sub = shift
    return sub.(_)
end

def increment_array
    self = shift
    return map { _+1 }_
end

def remember_wantarray
    self = shift
    last_wantarray = wantarray
    return 1
end
def return_last_wantarray
    self = shift
    return last_wantarray
end

=end

end 

