#!/usr/bin/env perl
use RMI::Client::Tcp; $c = RMI::Client::Tcp->new(); print $c,"\n"; while (<>) { eval { @r = $c->remote_eval("no strict; package main;\n" . $_); }; if ($@) { print "EXCEPTION: $@\n"; next }; print Data::Dumper::Dumper(\@r) }
