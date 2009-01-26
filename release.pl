#!/usr/bin/env perl
use strict;
use warnings;

my $mod = shift;
my $ver = shift;


use version;
my $qver = qv($ver);

eval "use lib './trunk/lib'; use $mod";
die $@ if $@;

my $mod_ver = do { no strict; ${ $mod . '::VERSION' } };
print "#module $mod has version $mod_ver (" . $mod_ver->numify . ").  expected $qver.\n";
unless ($mod_ver->numify == $qver) {
    die "version mismatch!";
}

print "svn cp trunk releases/${mod}-${ver}\n";
print "svn export releases/${mod}-${ver} uploads/${mod}-${ver}\n";
print "cp -r uploads/${mod}-${ver} x\n";
print "cd x; perl Makefile.PL; make; make test; cd ..\n";
print "cd uploads; tar -cvf ${mod}-${ver}.tar ${mod}-${ver}; gzip --best ${mod}-${ver}.tar; cd ..\n";


