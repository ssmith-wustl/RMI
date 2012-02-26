require 'rmi'
require 'rmi/server/forked-pipes'

class RMI::Client::ForkedPipes < RMI::Client
    attr_accessor :peer_pid


    @@rw = {}

    @@finalizer = Proc.new do |id|
        $RMI_DEBUG && print("#{$RMI_DEBUG_MSG_PREFIX} N:  Object #{id} dying at #{Time.new} reader/writer #{@@rw[id]}\n")
        @@rw.each do |handle| 
            handle.close
        end
    end

    def initialize(params = {}) 
        parent_reader = nil
        parent_writer = nil
        child_reader = nil
        child_writer = nil

        parent_reader, child_writer = IO.pipe
        child_reader, parent_writer = IO.pipe 
        child_writer.sync
        parent_writer.sync

        parent_pid = $$
        child_pid = fork {
            # child process acts as a server for this test and then exits...
            child_reader.close 
            child_writer.close
            
            # if a command was passed to the constructor, we exec() it.
            # this allows us to use a custom server, possibly one
            # in a different language..
            ##if (@_) {
            ##    exec(@_);   
            ##}
            
            # otherwise, we do the servicing in Perl
            $RMI_DEBUG_MSG_PREFIX = '  '
            server = RMI::Server::ForkedPipes.new(
                :peer_pid => parent_pid,
                :writer => parent_writer,
                :reader => parent_reader
            )
            server.run; 
            parent_reader.close 
            parent_writer.close
            exit
        }

        # parent/original process is the client which does tests
        parent_reader.close 
        parent_writer.close

        super
        @peer_pid = child_pid
        @writer = child_writer
        @reader = child_reader

        # ensure we call the finalizer to 
        @@rw[self.__id__] = [ @reader, @writer ]
        ObjectSpace.define_finalizer(self, @@finalizer)
    end 
end


=begin

=pod

=head1 NAME

RMI::Client::ForkedPipes - an RMI::Client implementation with a private out-of-process server

=head1 VERSION

This document describes RMI::Clinet::ForkedPipes v0.11.

=head1 SYNOPSIS

    $c1 = RMI::Client::ForkedPipes->new();
    $remote_hash1 = $c1->call_eval('{}');
    $remote_hash1{key1} = 123;

    $c2 = RMI::Client::ForkedPipes->new('some_server',$arg1,$arg2);    

=head1 DESCRIPTION

This subclass of RMI::Client forks a child process, and starts an
RMI::Server::ForkedPipes in that process.  It is useful for testing
more complex RMI, and also to do things like use two versions of
a module at once in the same program.

=head1 METHODS

=head2 peer_pid
 
 Both the RMI::Client::ForkedPipes and RMI::Server::ForkedPipes have a method to 
 return the process ID of their remote partner.

=head1 BUGS AND CAVEATS

See general bugs in B<RMI> for general system limitations of proxied objects.

=head1 SEE ALSO

B<RMI>, B<RMI::Server::ForkedPipes>, B<RMI::Client>, B<RMI::Server>, B<RMI::Node>, B<RMI::ProxyObject>

=head1 AUTHORS

Scott Smith <https://github.com/sakoht>

=head1 COPYRIGHT

Copyright (c) 2012 Scott Smith <https://github.com/sakoht>  All rights reserved.

=head1 LICENSE

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

The full text of the license can be found in the LICENSE file included with this
module.

=cut

=end

