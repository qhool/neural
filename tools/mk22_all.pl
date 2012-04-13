#!/usr/bin/perl
use warnings;
use strict;

use Data::Dumper;

if( @ARGV < 1 ) {
  print STDERR "usage: $0 <set_number>\n";
  exit(-1);
}

my $set_number = $ARGV[0];

#there are 256 possible 2 in, 2 out problems (4 input patterns * 4 output)
# and with each of these, 6 ways to make a 2 item training set, 
# and 4 ways to make a 1 item training set (order of training set is unimportant)
my @partitions = 
( [1,2],
  [1,3],
  [1,4],
  [2,3],
  [2,4],
  [3,4],
  [1],
  [2],
  [3],
  [4] );

my $outp = $set_number % 256;
my $partition_num = int($set_number / 256);

my @outbits = mkbits($outp, 8);
my @inbits = (0,0,0,1,1,0,1,1);

my @set;
for my $i (0..3) {
  push @set, "[[" . join( ",", @inbits[$i*2,$i*2+1] ) . "],[" .
    join( ",", @outbits[$i*2,$i*2+1] ) . "]]";
}

my $partition = $partitions[$partition_num];

my @train;
my @test;
my @partflags = (0)x4;
for my $n (@$partition) {
  $partflags[$n-1] = 1;
}
for my $i (0..3) {
  if( $partflags[$i] ) {
    push @train, $set[$i];
  } else {
    push @test, $set[$i];
  }
}

print "return\n";
print "  { TRAIN =>\n";
print "    [\n";
print "      " . join( ",\n      ", @train ), "\n";
print "    ],\n";
print "    TEST =>\n";
print "    [\n";
print "      " . join( ",\n      ", @test ), "\n";
print "    ],\n";
print "  };\n";

sub mkbits {
  my $n = shift;
  my $nbits = shift;
  my @bits = split( '', unpack( "b*", pack( "V", $n ) ) );
  return @bits[0..$nbits-1];
}



