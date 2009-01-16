#!/usr/bin/env perl
use strict;
use warnings;

use IO::Socket;
my $remote = IO::Socket::INET->new(
    Proto    => "tcp",
    PeerAddr => "127.0.0.1",
    PeerPort => 9000, 
) or die "cannot connect to daytime port at localhost: $!";
$remote->autoflush(1);
print $remote->getline,"\n";
for (1..10) {
    my $line = <>;
    $remote->print($line);
    print $remote->getline,"\n";
}

