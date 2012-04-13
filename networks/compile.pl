#!/usr/bin/perl
use warnings;
use strict;

use NetCompiler;

my $fname = $ARGV[0];
my $out = $ARGV[1];
my $nc = NetCompiler->new( filename => $fname );
$nc->compile( 'c', filename => "$out" );
