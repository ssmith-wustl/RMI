#!/usr/bin/env perl
use strict;
use warnings;

my $mod = shift;
my $ver = shift;

unless ($mod) {
    die "expecte module name as first param!";
}

unless ($ver) {
    die "expected version number as second param";
}

use version;
my $qver = qv($ver);

eval "use lib './trunk/lib'; use $mod";
die $@ if $@;

my $mod_ver = do { no strict; ${ $mod . '::VERSION' } };
print "#module $mod has version $mod_ver (" . $mod_ver->numify . ").  expected $qver.\n";
unless ($mod_ver->numify == $qver) {
    die "version mismatch!";
}

unless (grep { /$ver/ } `cat trunk/Changes`) {
    die "no version info for $ver in the Changes file";
}

print "svn cp trunk releases/${mod}-${ver}\n";
print "svn export releases/${mod}-${ver} uploads/${mod}-${ver}\n";
print "cp -r uploads/${mod}-${ver} x\n";
print "cd x; perl Makefile.PL; make; make test; cd ..; rm -rf x\n";
print "cd uploads; tar -cvf ${mod}-${ver}.tar ${mod}-${ver}; gzip --best ${mod}-${ver}.tar; rm -rf ${mod}-${ver}; cd ..\n";
print "svn add uploads/${mod}-${ver}.tar.gz\n";

