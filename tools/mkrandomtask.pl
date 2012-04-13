#!/usr/bin/perl
use warnings;
use strict;

use Data::Dumper;

if( @ARGV < 2 ) {
  print STDERR "Usage: $0 <num inputs> <num outputs>\n";
  exit(-1);
}

my $n_inputs = $ARGV[0];
my $n_outputs = $ARGV[1];

if( $n_outputs > 30 ) {
  print STDERR "$0: max of 30 outputs supported at this time\n";
  exit(-1);
}

my $n_patterns = 2**$n_inputs;

my @set;
for my $n (0..$n_patterns - 1) {
  my @bits = split( '', unpack( "b*", pack( "V", $n ) ) );
  my @inputs = @bits[0..$n_inputs - 1];
  @bits = split( '', unpack( "b*", pack( "V", int(rand( 2**31 )) ) ) );
  my @outputs = @bits[0..$n_outputs - 1];
  my $code = "[[" . join( ",", @inputs ) . "],[" . join ( ",", @outputs ) . "]]";
  push @set, $code;
}
my $ntrain = int($n_patterns / 3)+1;
my @train;
for my $i (1..$ntrain) {
  push @train, splice( @set, int(rand( @set+0 )), 1 );
}

print "return\n";
print "  { TRAIN =>\n";
print "    [\n";
print "      " . join( ",\n      ", @train ), "\n";
print "    ],\n";
print "    TEST =>\n";
print "    [\n";
print "      " . join( ",\n      ", @set ), "\n";
print "    ],\n";
print "  };\n";
