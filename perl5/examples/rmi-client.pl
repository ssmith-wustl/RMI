#!/usr/bin/env perl
use RMI::Client::Tcp;

my $c = RMI::Client::Tcp->new(
    host => 'localhost', 
    port => 1234,
);

for (1) {
    print "> ";
    my $src = <>;
    my $req = eval "$src";
    if ($@) {
        warn "error parsing message: $@";
        redo;
    }
    my @result = $c->call(@$req);
    print "# @result\n";
    redo;
}

