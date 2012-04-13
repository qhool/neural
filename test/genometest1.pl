#!/usr/bin/perl
use warnings;
use strict;


use strict;

use NetCompiler;

my $fname = $ARGV[0];

my $nc = NetCompiler->new( filename => $fname );
$nc->compile( 'genome', 
	      filename => "$fname.gen" );

my $nc2 = NetCompiler->new( filename => "$fname.gen",
			    genome_mode => 1 );
$nc2->compile( 'graphviz', filename => "$fname.gen.dot" );
system( "dot -T ps -o $fname.gen.ps $fname.gen.dot" );
system( "gv $fname.gen.ps" );

#print Data::Dumper::Dumper( $nc2 );

