#!/usr/bin/perl
use warnings;
use strict;


use strict;

use NetCompiler;

my $fname = $ARGV[0];
my $nc = NetCompiler->new( filename => "$fname.net" );
$nc->compile( 'c', filename => "$fname.c" );
