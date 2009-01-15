package RMI::Client::ForkedPipes;

use strict;
use warnings;
use version;
our $VERSION = qv('0.1');

use base 'RMI::Client';

use IO::Handle;     # "thousands of lines just for autoflush":(

RMI::Node::_mk_ro_accessors(__PACKAGE__,'peer_pid');

sub new {
    my $class = shift;
    
    my $parent_reader;
    my $parent_writer;
    my $child_reader;
    my $child_writer;
    pipe($parent_reader, $child_writer);  
    pipe($child_reader,  $parent_writer); 
    $child_writer->autoflush(1);
    $parent_writer->autoflush(1);
    
    my $parent_pid = $$;
    my $child_pid = fork();
    die "cannot fork: $!" unless defined $child_pid;
    unless ($child_pid) {
        # child process acts as a server for this test and then exits...
        close $child_reader; close $child_writer;
        
        # if a command was passed to the constructor, we exec() it.
        # this allows us to use a custom server, possibly one
        # in a different language..
        if (@_) {
            exec(@_);   
        }
        
        # otherwise, we do the servicing in Perl
        $RMI::DEBUG_MSG_PREFIX = '  ';
        my $server = RMI::Server->new(
            peer_pid => $parent_pid,
            writer => $parent_writer,
            reader => $parent_reader,
        );
        $server->run; 
        close $parent_reader; close $parent_writer;
        exit;
    }

    # parent/original process is the client which does tests
    close $parent_reader; close $parent_writer;

    my $self = $class->SUPER::new(
        peer_pid => $child_pid,
        writer => $child_writer,
        reader => $child_reader,
    );

    return $self;    
}

1;


=pod

=head1 NAME

RMI::Client::ForkedPipes


=head1 SYNOPSIS

    $c1 = RMI::Client::ForkedPipes->new();
    $remote_hash1 = $c1->remote_eval('{}');
    $remote_hash1{key1} = 123;
    
=head1 DESCRIPTION

This subclass of RMI::Client makes a TCP/IP socket connection to an
B<RMI::Server::Tcp>.  See B<RMI::Server::Tcp> for details on server options.  

=back

=head1 METHODS

This class overrides the constructor for a default RMI::Client to make a
socket connection.  That socket is both the reader and writer handle for the
client.

=head1 BUGS AND CAVEATS

See general bugs in B<RMI> for general system limitations of proxied objects.

=head1 SEE ALSO

B<RMI>, B<RMI::Server::Tcp>, B<RMI::Client>, B<RMI::Server>, B<RMI::Node>, B<RMI::ProxyObject>

=cut
