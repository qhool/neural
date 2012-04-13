#!/usr/bin/perl
use warnings;
use strict;

if( @ARGV < 4 ) {
  print STDERR "Usage: $0 <arg A inputs> <arg B inputs> <num outputs> <op>\n";
  exit(-1);
}

my $n_a_bits = $ARGV[0];
my $n_b_bits = $ARGV[1];
my $n_outputs = $ARGV[2];

my $n_inputs = $n_a_bits + $n_b_bits;
my $op = $ARGV[3];
if( $op eq 'plus' or $op eq 'add' or $op eq '+') {
  $op = '+';
} else {
  $op = '*';
}

my @set;
for my $a (0..(2**$n_a_bits-1)) {
  for my $b (0..(2**$n_b_bits-1)) {
    my $out;
    if( $op eq '+' ) {
      $out = $a + $b;
    } else {
      $out = $a * $b;
    }
    push @set, "[[" . bitscode($a,$n_a_bits) . "," . bitscode($b,$n_b_bits) .
      "],[" . bitscode($out,$n_outputs) . "]]";
  }
}

my $ntrain = int((@set+0)/3)+1;
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

sub mkbits {
  my $n = shift;
  my $nbits = shift;
  my @bits = split( '', unpack( "b*", pack( "V", $n ) ) );
  return @bits[0..$nbits-1];
}

sub bitscode {
  my $n = shift;
  my $nbits = shift;
  return join( ",", mkbits( $n,$nbits ) );
}
