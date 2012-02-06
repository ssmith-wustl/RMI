require 'weakref'

class RMI::RequestResponder

    def initialize(node)
        @node = WeakRef.new(node)
    end

end

