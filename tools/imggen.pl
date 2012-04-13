#!/usr/bin/perl
use warnings;
use strict;

use strict;

use NetCompiler;

use Getopt::Long;

my $display = 1;
my $show_discon = 1;
GetOptions( "display!" => \$display,
	    "disconnected!" => \$show_discon );
my %comp_args;
unless( $show_discon ) {
  %comp_args = ( no_disconnected => 1 );
}

my $fname = $ARGV[0];
my $psname = $ARGV[1];
my @rm_files;
unless( defined $psname ) {
  $psname = `mktemp`;
  chomp $psname;
  push @rm_files, $psname;
}
my $dotfile = `mktemp`;
chomp $dotfile;
push @rm_files, $dotfile;
my %args;
if( $fname =~ /\.gen$/ ) {
  %args = ( genome_mode => 1 );
  print STDERR "loading genome\n";
}
my $nc = NetCompiler->new( %args, filename => $fname );
$nc->compile( 'graphviz', filename => "$dotfile", %comp_args );
system( "dot -T ps -o $psname $dotfile" );
if( $display ) {
  system( "gv $psname" );
}
unlink( @rm_files );
