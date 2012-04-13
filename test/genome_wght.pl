#!/usr/bin/perl -w
use strict;
use lib "../";

use NetCompiler::Genome;

while( my $wght = <> ) {
  my $encoded = NetCompiler::Genome::encode_weight( $wght );
  print "Encoded as $encoded / ", unpack( "B*", $encoded >> 8 ),
    unpack( "B*", $encoded % 2**8 ), "\n";
  my $packun = unpack( "n", pack( "n", $encoded ) );
		      
  my $decoded = NetCompiler::Genome::decode_weight( $packun );
  print "Decoded to: $decoded\n";
  my $err = (abs( $wght - $decoded ) / $wght ) * 100;
  printf "%0.2f%% error\n", $err;
}
