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

