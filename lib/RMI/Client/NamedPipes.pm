package RMI::Client::NamedPipes;

use strict;
use warnings;
use version;
our $VERSION = qv('0.1');

use base 'RMI::Client';

use IO::File; # need autoflush

sub new {
    my ($class, %params) = (@_);
    my $reader_path = $params{reader_path};
    my $writer_path = $params{writer_path};
    my $reader = IO::File->new($reader_path);
    $reader or die "Failed to open reader $reader_path: $!";
    my $writer = IO::File->new('>' . $writer_path);
    $writer or die "Failed to open writer $writer_path: $!";
    $writer->autoflush(1);
    my $self = $class->SUPER::new(
        peer_pid => -1,
        writer => $writer,
        reader => $reader,
    );
    return $self;    
}

1;


=pod

=head1 NAME

RMI::Client::Tcp - do RMI over a TCP/IP socket


=head1 SYNOPSIS

# in a server process

    $s = RMI::Client->new(
        reader_path => '/my/client_to_server',
        writer_path => '/my/server_to_client',
    );

# in a client process:

    $c = RMI::Client->new(
        reader_path => '/my/server_to_client',
        writer_path => '/my/client_to_server',
    );
    $c->call_use('IO::File');
    $remote_fh = $c->call_class_method('IO::File', 'new', '/my/file');
    print <$remote_fh>;
    
=head1 DESCRIPTION

This subclass of RMI::Client uses a pair of handles

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

