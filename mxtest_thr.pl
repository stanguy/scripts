#! /usr/bin/perl -w
# @(#)mxtest.pl
# Author: Sebastien Tanguy <seb+scripts@death-gate.fr.eu.org>
# Version: $Id: mxtest.pl,v 1.4 2003/05/01 16:46:08 seb Exp $


use Net::DNS;
use Net::SMTP;

use threads;
use threads::shared;

my $NUMBER_THREADS = 4;

my $debug : shared = 0;

my $domain = $ARGV[0];
my $resolver = Net::DNS::Resolver->new;
my @mx = mx( $resolver, $domain );
my @all_mx : shared;

####
# First, we need  to resolve the domain and find  the IP addresses for
# the MX of this domain.
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


####
# This is the hash that will contain the results.
my %tested_mx : shared ;
# our threads
my @running_threads;

# launch the threads
for ( 0 .. $NUMBER_THREADS ) {
    push @running_threads, threads->new( \&thr_test_mx );
}

# now, wait for them to complete their work.
while ( @running_threads ) {
    $running_threads[0]->join;
    shift @running_threads;
}

# Now, let's count the results.
my $mx_ok = 0;
my $mx_total = 0;

foreach my $ip ( keys %tested_mx ) {
    if ( $tested_mx{ $ip } ) {
        ++$mx_ok;
    }
    ++$mx_total;
}

# And print the results.
print $mx_ok, " / ", $mx_total, "\n";


# Our threads.
sub thr_test_mx {

    my $current_mx;
    # try to get a first MX to test
  LOCK_INIT_MX: {
        lock( @all_mx );
        $current_mx = shift @all_mx;
    }
    my $nb_tests = 0;
    while ( $current_mx ) {

        # we have a server to test:
        my $this_smtp = 0;
        my $smtp = Net::SMTP->new( $current_mx, Timeout => 2 );

        if ( $smtp ) {
            $smtp->quit();
            $this_smtp = 1;
        }
        # we store the result
      LOCK_DONE: {
            lock( %tested_mx );
            $tested_mx{ $current_mx } = $this_smtp;
        }
        # we try to retrieve the next server
      LOCK_NEXT_MX: {
            lock( @all_mx );
            $current_mx = shift @all_mx;
        }
        # for debugging purposes.
        $nb_tests++;
        print "I am thread ", threads->tid(), 
          " and i have done ", $nb_tests, " request\n" if $debug;
    }

}
