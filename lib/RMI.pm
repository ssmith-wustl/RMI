
package RMI;

use strict;
use warnings;

use RMI::Client;
use RMI::Server;
use RMI::ProxyObject;

use Data::Dumper;

BEGIN { $RMI::DEBUG = $ENV{RMI_DEBUG}; };
our $DEBUG_INDENT = '';
our $DEBUG;

# client

sub _convert_references {
    my ($sent,$received,@p) = @_;
    my @px;
    for my $p (@p) {
        if (ref($p)) {
            if ($received->{$p}) {
                #push @px, 2, $key;
                die "received $p?"
            }
            elsif ($p->isa("RMI::ProxyObject")) {
                my $key = $$p;
                print "$DEBUG_INDENT C: $$ proxy $p references remote $key:\n" if $RMI::DEBUG;
                push @px, 2, $key;
            }
            else {
                my $key = "$p";
                push @px, 1, $key;
                $sent->{$key} = $p;
            }
        }
        else {
            push @px, 0, $p;
        }
    }
    return @px;
}

sub send_query {
    my ($hout, $hin, $sent, $received, $o, $m, @p) = @_;
    my @px = _convert_references($sent,$received,$o,@p);
    my $s = Data::Dumper::Dumper(['query',$m,@px]);
    $s =~ s/\n/ /gms;
    print "$DEBUG_INDENT C: $$ sending $s\n" if $DEBUG;
    my $r = $hout->print($s,"\n");
    unless (defined $r) {
        Carp::confess("failed to send: $!");
    }
    return $r;
}

sub receive_result {
    my ($hin,$hout, $sent, $received, $client_pid) = @_;
    $client_pid = -1;
    while (1) {
        print "$DEBUG_INDENT C: $$ receiving\n" if $DEBUG;
        my $incoming_text = $hin->getline;
        if (not defined $incoming_text) {
            die "Undef result?";
        }
        print "$DEBUG_INDENT C: $$ got $incoming_text" if $DEBUG;
        print "\n" if $DEBUG and not defined $incoming_text;
        my $incoming_data = eval "no strict; no warnings; $incoming_text";
        if ($@) {
            die "Exception: $@";
        }
        my $type = shift @$incoming_data;
        if ($type eq 'result') {
            print "$DEBUG_INDENT C: $$ returning @$incoming_data\n" if $DEBUG;
            return _convert_stream($hin, $sent,$received,@$incoming_data);            
        }
        elsif ($type eq 'query') {
            no warnings;
            print "$DEBUG_INDENT C: $$ running @$incoming_data\n" if $DEBUG;
            my @result = process_query(
                $hin,
                $hout,
                $sent,
                $received,
                $client_pid,
                $incoming_data
            );
            print "$DEBUG_INDENT C: $$ sending back @result\n" if $DEBUG;
            send_result($hout,$sent,$received,@result);            
        }
        else {
            die "unexpected type $type";
        }
    }
}

# server

sub eval {
    my $src = shift;
    my @result = eval $src;
    die $@ if $@;
    return @result;
}

sub serve {
    my ($hin,$hout, $sent, $received, $client_pid) = @_;
    $sent ||= {};
    $received ||= {};
    $RMI::server_for_id{$hin} = [ $hout, $hin, $sent, $received ];
    while (1) {
        print "$DEBUG_INDENT S: $$ waiting\n" if $DEBUG;
        my $incoming_text = $hin->getline;
        if (not defined $incoming_text) {
            print "$DEBUG_INDENT S: $$ shutting down\n" if $DEBUG;
            last;
        }
        print "$DEBUG_INDENT S: $$ got $incoming_text" if $DEBUG;
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
            print "$DEBUG_INDENT S: $$ running @$incoming_data\n" if $DEBUG;
            my @result = process_query(
                $hin,
                $hout,
                $sent,
                $received,
                $client_pid,
                $incoming_data
            );
            print "$DEBUG_INDENT S: $$ sending back @result\n" if $DEBUG;
            send_result($hout,$sent,$received,@result);
        }
    }
}

sub _convert_stream {
    my ($hin, $s, $r, @px) = @_;
    my @p;
    while (@px) { 
        my $type = shift @px;
        my $value = shift @px;
        if ($type == 0) {
            # primitive value
            print "$DEBUG_INDENT S: $$ - primitive $value\n" if $DEBUG;
            push @p, $value;
        }   
        elsif ($type == 1) {
            # exists on the other side: make a proxy
            my $o = \$value;
            bless $o, "RMI::ProxyObject";
            $r->{$value} = $o;
            push @p, $o;
            $RMI::server_id_for_remote_object{"$o"} = $hin;
            print "$DEBUG_INDENT S: $$ - made proxy for $value\n" if $DEBUG;
        }
        elsif ($type == 2) {
            # was a proxy on the other side: get the real object
            my $o = $s->{$value};
            die "no object $o!" unless $o;
            push @p, $o;
            print "$DEBUG_INDENT S: $$ - resolved local object for $value\n" if $DEBUG;
        }
    }
    return @p;    
}
sub process_query {
    my ($hin,$hout,$s,$r,$client_pid,$incoming_data) = @_;
    my ($m,@px) = @$incoming_data;
    print "$DEBUG_INDENT S: $$ got params @px\n" if $DEBUG;
    my @p = _convert_stream($hin,$s,$r,@px);
    print "$DEBUG_INDENT S: $$ got values @p\n" if $DEBUG;
    my $o = shift @p;
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
    my ($h, $sent, $received, @r) = @_;
    my $s = Data::Dumper::Dumper(['result', _convert_references($sent, $received, @r)]);   
    $s =~ s/\n/ /gms;
    $h->print($s,"\n");
}


1;

