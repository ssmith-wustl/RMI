
package RMI;
use strict;
use warnings;
use Data::Dumper;

BEGIN { $RMI::DEBUG = $ENV{RMI_DEBUG}; };
our $DEBUG;

# client
sub call {
    my ($hout, $hin, $o, $m, @p) = @_;
    my $os = $o || '<none>';
    print " C: calling $os $m @p\n" if $DEBUG;
    unless (send_query($hout,$o,$m,@p)) {
        die "failed to send!";
    }
    my @result = recieve_result($hin,$hout);
    return @result;
}

sub send_query {
    my ($hout, $o, $m, @p) = @_;
    my $s = Data::Dumper::Dumper(['query',$o,$m,@p]);
    $s =~ s/\n/ /gms;
    $hout->print($s,"\n");
}

sub recieve_result {
    my ($hin,$hout) = @_;
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
    my ($hin,$hout) = @_;
    while (1) {
        print "  S: waiting\n" if $DEBUG;
        my $incoming_text = $hin->getline;
        if (not defined $incoming_text) {
            print "  S: shutting down\n";
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
            my @result = process_query(@$incoming_data);
            print "  S: sending back @result\n" if $DEBUG;
            send_result($hout,@result);
        }
    }
}

sub process_query {
    my ($o,$m,@p) = @_;
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

