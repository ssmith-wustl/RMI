
package RMI;
use strict;
use warnings;
use Data::Dumper;
use RMI::ProxyObject;

BEGIN { $RMI::DEBUG = $ENV{RMI_DEBUG}; };
our $DEBUG;

# client
sub call {
    my ($hout, $hin, $sent, $received, $o, $m, @p) = @_;
    my $os = $o || '<none>';
    print " C: calling $os $m @p\n" if $DEBUG;
    unless (send_query($hout,$hin,$sent,$received,$o,$m,@p)) {
        die "failed to send!";
    }
    my @result = receive_result($hin,$hout, $sent, $received);
    return @result;
}

sub send_query {
    my ($hout, $hin, $sent, $received, $o, $m, @p) = @_;
    my @px;
    for my $p (@p) {
        if (ref($p)) {
            my $key = "$p";
            push @px, 1, $key;
            $sent->{$key} = $p;
        }
        else {
            push @px, 0, $p;
        }
    }
    my $s = Data::Dumper::Dumper(['query',$o,$m,@px]);
    $s =~ s/\n/ /gms;
    $hout->print($s,"\n");
}

sub receive_result {
    my ($hin,$hout, $sent, $received) = @_;
    while (1) {
        print " C: receiving\n" if $DEBUG;
        my $incoming_text = $hin->getline;
        if (not defined $incoming_text) {
            die "Undef result?";
        }
        print " C: got $incoming_text" if $DEBUG;
        print "\n" if $DEBUG and not defined $incoming_text;
        my $incoming_data = eval "no strict; no warnings; $incoming_text";
        if ($@) {
            die "Exception: $@";
        }
        my $type = shift @$incoming_data;
        if ($type ne 'result') {
            die "unexpected type $type";
        }
        else {
            print " C: returning @$incoming_data\n" if $DEBUG;
            return @$incoming_data;
        }
    }
}

# server 
sub serve {
    my ($hin,$hout,$data) = @_;
    my $sent = {};
    my $received = {};
    while (1) {
        print "  S: waiting\n" if $DEBUG;
        my $incoming_text = $hin->getline;
        if (not defined $incoming_text) {
            print "  S: shutting down\n" if $DEBUG;
            last;
        }
        print "  S: got $incoming_text" if $DEBUG;
        my $incoming_data = eval "no strict; no warnings; package main; $incoming_text";
        if ($@) {
            die "Exception: $@";
        }
        my $type = shift @$incoming_data;
        if ($type ne 'query') {
            die "unexpected type $type";
        }
        else {
            no warnings;
            print "  S: running @$incoming_data\n" if $DEBUG;
            my @result = process_query($sent,$received,@$incoming_data);
            print "  S: sending back @result\n" if $DEBUG;
            send_result($hout,@result);
        }
    }
}

sub process_query {
    my ($s,$r,$o,$m,@px) = @_;
    my @p;
    print "  S: got params @px\n" if $DEBUG;
    while (@px) { 
        my $type = shift @px;
        my $value = shift @px;
        if ($type == 0) {
            # primitive value
            print "  S: - primitive $value\n" if $DEBUG;
            push @p, $value;
        }   
        elsif ($type == 1) {
            # exists on the other side: make a proxy
            my $o = \$value;
            bless $o, "RMI::Proxy";
            $r->{$value} = $o;
            push @p, $o;
            print "  S: - made proxy for $value\n" if $DEBUG;
        }
        elsif ($type == 2) {
            # was a proxy on the other side: get the real object
            my $o = $s->{$value};
            die "no object $o!" unless $o;
            push @p, $o;
            print "  S: - resolved local object for $value\n" if $DEBUG;
        }
    }
    print "  S: got values @p\n" if $DEBUG;
    my @r;
    if (defined $o) {
        @r = $o->$m(@p);
    }
    else {
        no strict 'refs';
        @r = $m->(@p);
    }
    return @r;
}

sub send_result {
    my ($h, @r) = @_;
    my $s = Data::Dumper::Dumper(['result',@r]);   
    $s =~ s/\n/ /gms;
    $h->print($s,"\n");
}

1;

