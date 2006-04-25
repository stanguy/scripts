#! /usr/bin/perl -w
# @(#)mxtest.pl
# Author: Sebastien Tanguy <seb+scripts@death-gate.fr.eu.org>
# Version: $Id: mxtest.pl,v 0.0 2002/12/01 22:11:52 seb Exp $


use Net::DNS;
use Net::SMTP;

my $debug = 0;

my $domain = $ARGV[0];
my $resolver = Net::DNS::Resolver->new;
my @mx = mx( $resolver, $domain );

my @all_mx;

if ( @mx ) {
    foreach my $rr_mx ( @mx ) {
        print "*** Resolving ", $rr_mx->exchange, "\n" if $debug;

        my $answer = $resolver->search( $rr_mx->exchange );
        if ( $answer ) {
            foreach my $rr_ans ( $answer->answer ) {
                next if not $rr_ans->type eq "A";
                print "+++ Found: ", $rr_ans->address, "\n" if $debug ;
                push @all_mx, $rr_ans->address;
            }
        }

    }
}


my $total_mx = 0;
my $total_good_mx = 0;

foreach my $ip ( @all_mx ) {
    $total_mx ++;
    if ( test_mx( $ip ) ) {
        $total_good_mx ++;
    }
}

print $total_good_mx, " / ", $total_mx,"\n" ;

sub test_mx {
    my $ip = shift;

    my $smtp = Net::SMTP->new( $ip, Timeout => 5 );

    if ( $smtp ) {
        $smtp->quit();
        return 1;
    }
    return 0;
}
