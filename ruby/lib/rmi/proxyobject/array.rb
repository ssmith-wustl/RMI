
class RMI::ProxyObject::Array < RMI::ProxyObject
    def to_a
        a = []
        self.length.times do |n|
            a[n] = self[n]
        end
        return a
    end
end

