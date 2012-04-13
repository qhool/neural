#!/usr/bin/perl -w
use strict;

use Data::Dumper;

my @nums;

for my $n (0..127) {
  my @bits = split( '', unpack( "B*", pack( "C", $n ) ) );
  #remove the 8th (high) bit:
  shift @bits;
  my $sum = 0;
  for my $bit (@bits) {
    $sum += $bit;
  }
  my @sumbits = split( '', unpack( "B*", pack( "C", $sum ) ) );
  #remove all but last 3 bits:
  splice( @sumbits, 0, 5 );
  my $code = "[[" . join( ",", @bits ) . "],[" . join ( ",", @sumbits ) . "]],";
  push @{$nums[$sum]}, $code;
}

#print Data::Dumper::Dumper( \@nums );

print "return\n";
print "  { TRAIN =>\n";
print "    [\n";
for my $i (0..7) {
  print "     # $i\n";
  my @set = @{$nums[$i]};
  my @rndset;
  if( @set == 1 ) {
    print "     $set[0]\n";
  } else {
    @rndset = randlist( @set );
    for my $i (0..2) {
      my $itm = shift @rndset;
      print "     $itm\n";
    }
  }
  $nums[$i] = \@rndset;
}
print "    ],\n";
print "    TEST =>\n";
print "    [\n";
for my $i (0..7) {
  print "     # $i\n";
  my @set = @{$nums[$i]};
  for my $itm (@set) {
    print "     $itm\n";
  }
}
print "    ],\n";
print "  };\n";

sub randlist {
  my @tmp = map { { R => rand(), OBJ => $_ } } @_;

  @tmp = (sort { $a->{R} <=> $b->{R} } @tmp );

  return (map { $_->{OBJ} } @tmp);
}
  
