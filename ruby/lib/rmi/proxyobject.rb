require "rmi"
require "rmi/proxymethods"

class RMI::ProxyObject
    include RMI::ProxyMethods
end

=begin

=pod

=head1 NAME

RMI::ProxyObject - used internally by RMI for "stub" objects

=head1 VERSION

This document describes RMI::ProxyObject v0.11.

=head1 DESCRIPTION

This class is the real class of all transparent proxy objects, though
objects of this class will attempt to hide that fact.

This is an internal class used by B<RMI::Client> and B<RMI::Server>
nodes.  Objects of this class are never constructed explicitly by
applications.  They are made as a side effect of data passing
between client and server.  Any time an RMI::Client or RMI::Server 
"passes" an object as a parameter or a return value, an RMI::ProxyObject 
is created on the other side.  

Note that RMI::ProxyObjects are also "tied" to the module 
B<RMI::ProxyReference>, which handles attempts to use the reference 
as a plain Ruby reference.

The full explanation of how references, blessed and otherwise, are
proxied across an RMI::Client/RMI::Server pair (or any RMI::Node pair)
is in B<RMI::ProxyReference>.

=head1 METHODS

The goal of objects of this class is to simulate a specific object
on the other side of a specific RMI::Node (RMI::Client or RMI::Server).
As such, this does not have its own API.  

This class does, however, overridefour special Ruby methods in ways which 
are key to its ability to proxy method calls:

=head2 AUTOLOAD

AUTOLOAD directs all method calls across the connection which created it 
to the remote side for actual execution.

=head2 isa

Since calls to isa() will not fire AUTOLOAD, isa() is explicitly overridden
to redirect through the RMI::Node which owns the object in question.

=head2 can 

Since calls to can() will also not fire AUTOLOAD, we override can() explicitly
as well to redirect through the RMI::Node which owns the object in question.

=head2 DESTROY

The DESTROY handler manages ensuring that the remote side reduces its reference
count and can do correct garbage collection.  The destroy handler on the other
side will fire as well at that time to do regular cleanup.

=head1 BUGS AND CAVEATS

=head2 the proxy object is only MOSTLY transparent

Ways to detect that an object is an RMI::ProxyObject are:

 1. ref($obj) will return "RMI::ProxyObject" unless the entire class
has been proxied (with $client->use_remote('SomeClass').

 2. "$obj" will stringify to "RMI::ProxyObject=SOMETYPE(...)", though
this will probaby be changed at a future date.

See general bugs in B<RMI> for general system limitations of proxied objects.

=head1 SEE ALSO

B<RMI>, B<RMI::Client>, B<RMI::Server>,B<RMI::ProxyReference>, B<RMI::Node>

=head1 AUTHORS

Scott Smith <https://github.com/sakoht>

=head1 COPYRIGHT

Copyright (c) 2012 Scott Smith <https://github.com/sakoht>  All rights reserved.

=head1 LICENSE

This program is free software you can redistribute it and/or modify it under
the same terms as Ruby itself.

The full text of the license can be found in the LICENSE file included with this
module.

=cut

=end


