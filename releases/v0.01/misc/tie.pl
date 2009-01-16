#!/usr/bin/env perl
use strict;
use warnings;
use Tie::Array;

my $a = [1,2,3];
tie @$a, 'MyArray', @$a;
print ">@$a\n";
@$a = (4,5,6);
print ">@$a\n";
bless $a, "Foo";
MyArray::STORE($a,3,999);
print $a->foo,"\n";
print ">@$a\n";
exit;

#$o = undef;
#print "@$a\n$a\n$o\n";

package MyArray;
#use base 'Tie::StdArray';

sub TIEARRAY {
    my $class = shift;
    my $x = [@_];
    my $o = bless $x, $class;
    print "$class $x $o @_\n";
    return $o;
}

sub AUTOLOAD {
    my $m = $MyArray::AUTOLOAD;
    $m =~ s/MyArray:://;
    print "a: $m @_\n";
    my $d = Tie::StdArray->can($m);
    $d->(@_);
}

package Foo;

sub foo {
    123;
}

1;

