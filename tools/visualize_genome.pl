#!/usr/bin/perl
use strict;

use NetCompiler;
use NetCompiler::Genome;
use Mutation;
use Carp;

my $filename = $ARGV[0];

my $in = new IO::File( "<$filename" ) 
  or die "Can't open genome file ($filename): $!";

my $immutable_color = 'Yellow';
my $ignored_color = 'Gray';
my $start_color = 'LimeGreen';
my $end_color = 'Red';
my $rand_color = 'CornflowerBlue';
my $neg_color = 'CarnationPink';
my $pos_color = 'White';
my $before_color = 'LimeGreen';
my $after_color = 'Orchid';
my $feedback_color = 'Cerulean';
my $input_color = 'GreenYellow';
my $preamble = '\begin{supertabular}{r|l}' . "\n";
my $postamble = '\end{supertabular}' . "\n";

print $preamble;
my $opt_count = NetCompiler::_genome_immutable_options_count();
my $known_count = 2;
my $n_inputs = read_int( $in );
fmt_line( $n_inputs, "$n_inputs inputs. (immutable)", $immutable_color );
my $n_outputs = read_int( $in );
fmt_line( $n_inputs, "$n_outputs outputs. (immutable)", $immutable_color );
for my $i (1..($opt_count - $known_count)) {
  fmt_line( read_int( $in ), "Unknown option. (immutable)", $immutable_color );
}
my @ints;
my $in_node = 0;
my $node_count = 0;

while( not $in->eof() ) {
  my $int = read_int( $in );
  push @ints, $int;
  if( not $in_node and NetCompiler::_is_node_start( $int ) ) {
    $in_node = 1;
    $node_count++;
  }
  elsif( $in_node and NetCompiler::_is_node_end( $int ) ) {
    $in_node = 0;
  }
}

$in_node = 0;
my $node_num = $n_inputs;
my $intron_posn = 0;
for my $int (@ints) {
  if( $in_node ) {
    if( NetCompiler::_is_node_end( $int ) ) {
      fmt_line( $int, "END", $end_color, $ignored_color );
      $in_node = 0;
      $intron_posn = 0;
      $node_num++;
    }
    else {
      my $weight = NetCompiler::Genome::decode_weight( $int>>16 );
      my $con = $int % 2**16;
      my $pwr = 15;
      while( $con >= ( $node_count + $n_inputs ) ) {
	$con = $int % (2**$pwr);
	$pwr--;
      }
      my $con_str = "Node " . ( $con - $n_inputs );
      if( $con < $n_inputs ) {
	$con_str = "Input $con";
      }
      my $weight_str = 'random weight';
      my $weight_color = $rand_color;
      if( defined $weight ) {
	$weight_str = "weight $weight";
	$weight_color = $pos_color;
	if( $weight < 0 ) {
	  $weight_color = $neg_color;
	}
      }
      my $con_color = $after_color;
      if( $con < $n_inputs ) {
	$con_color = $input_color;
      }
      elsif( $con < $node_num ) {
	$con_color = $before_color;
      }
      elsif( $con == $node_num ) {
	$con_color = $feedback_color;
      }
      fmt_line( $int, "$weight_str from $con_str",
		$weight_color, $weight_color, $con_color, $con_color );
    }
  }
  elsif( NetCompiler::_is_node_start( $int ) ) {
    my $disp_num = $node_num - $n_inputs;
    fmt_line( $int, "START node $disp_num" .
	      (($node_count - $node_num < $n_outputs)?' (output node)':''),
	      $start_color, $ignored_color );
    $in_node = 1;
  } else {
    fmt_line( $int, ($intron_posn == 0)?'INTRON':'  "', $ignored_color );
    $intron_posn++;
  }
}

print $postamble;

sub read_int {
  my $in = shift;

  my $bytes = Mutation::read_bytes( $in, 4 );
  return unpack( "N", $bytes );
}

sub fmt_line {
  my $int = shift;
  my $comment = shift;
  my @colors = @_;

  if( @colors == 0 ) {
    croak "can't have empty color list\n";
  }

  if( @colors < 4 ) {
    #assume last color repeats
    push @colors, ( $colors[$#colors] ) x (4 - @colors);
  }

  #print STDERR join( ':', @colors ), "\n";

  my @hexdig = split( '', unpack( "H*", pack( "N", $int ) ) );
  my @hexbytes;
  while( @hexdig ) {
    push @hexbytes, (shift( @hexdig ) . shift( @hexdig ) );
  }
  #print STDERR join( " ", @hexbytes ), " | $comment\n";
  for my $i (0..3) {
    print '\colorbox{' . $colors[$i] . '}{\parbox{12pt}{' . $hexbytes[$i] . '}}';
  }
  print '&' . $comment . '\\\\' . "\n";
}
