
package RMI::ProxyObject;

sub new {
    my $class = shift;
    my $self = bless { @_ }, $class;
    return $self;
}

sub AUTOLOAD {
    my $object = shift;
    my $method = $AUTOLOAD;
 
}


1;

