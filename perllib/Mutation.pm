=head1 NAME

Mutation - mutate binary neural network genomes used by NetCompiler

=head1 SYNOPSIS

 use Mutation;
 mutate_genome( <infile>, <outfile>, <mutation_level> );
 cross_genomes( <in1>, <in2>, <outfile> [, optional args] );
 purge_introns( <infile>, <outfile> );

=head1 DESCRIPTION

Mutation implements fairly brain-dead mutation and crossover functionality for network genomes.  These functions only know that the genetic code is composed of 4-byte blocks.

=head1 INTERFACE

=over

=cut

package Mutation;

use Carp qw(croak);

use NetCompiler;

=item mutate_genome( <infile>, <outfile>, <mutation_level> )

Makes an imperfect copy of infile to outfile.  The <mutation_level> specifies how many randomly selected data-altering operations to perform per 1000 four-byte blocks.  Each operation performed is either a single block deletion, insertion, or replacement with a random value, or a multi-block move operation.  The move operation selects a 5-100 block segment and transposes it to a new location within about a thousand blocks of the starting point.

=cut

sub mutate_genome {
  my $in_filename = shift;
  my $out_filename = shift;
  # mutation level goes from 0 to 100
  # this represents the number of integer alterations in 1000 ints
  my $mutation_level = shift;
  if( @_ ) {
    $mutation_level = shift;
  }

  #mutation methods:
  # changes to single ints:
  #   change value
  #   insert new
  #   delete
  # displace a section

  #NetCompiler::_is_node_start( $n );

  my $in = new IO::File( "<$in_filename" )
    or croak( "Can't open source genome ($in_filename): $!" );

  my $out = new IO::File( ">$out_filename" )
    or croak( "Can't open output ($out_filename): $!" );

  # skip over the immutable options
  my $buf;
  my $immutable_len = NetCompiler::_genome_immutable_options_count() * 4;
  my $len = $in->read( $buf, $immutable_len );
  unless( $len == $immutable_len ) {
    die "Can't even read immutable options: $!";
  }

  print $out ( $buf );
  my $remainderbuf;
  while( not $in->eof() ) {
    $len = $in->read( $buf, 2000 * 4 );
    if( defined $remainderbuf ) {
      $len += length( $remainderbuf );
      $buf = $remainderbuf . $buf;
      undef $remainderbuf;
    }
    my $int_count = int($len/4);
    my $remainder = $len % 4;
    my $mutacount = int(($int_count/1000) * $mutation_level) + 1;
    my $intbuf = substr( $buf, 0, $int_count * 4 );
    if( $remainder ) {
      $remainderbuf = substr( $buf, $int_count * 4, $remainder );
    }
    undef $buf;
    #turn the bytes into an array of integers:
    my @ints = unpack( "N*", $intbuf );
    #now decide what mutation events will occur
    my $alter_count = 0;
    my $insert_count = 0;
    my $delete_count = 0;
    my $relocate_count = 0;
    for my $i (1..$mutacount) {
      my $type = int(rand(4));
      if( $type == 0 ) { $alter_count++; }
      elsif( $type == 1 ) { $insert_count++; }
      elsif( $type == 2 ) { $delete_count++; }
      else { $relocate_count++; }
    }
    while( $relocate_count ) {
      my $relocate_len = int(rand(96)) + 5;
      if( $relocate_len > $relocate_count ) {
	$relocate_len = $relocate_count;
      }
      $relocate_count -= $relocate_len;
      # select from all starting/ending points s.t. there is enough stuff after
      my $move_from = int(rand($int_count - $relocate_len)) + 1;
      my $move_to = int(rand($int_count - $relocate_len)) + 1;
      #print "Relocating $relocate_len integers from $move_from to $move_to\n";
      # divide array into: |---pre move---|---moved---|---post move---|
      my $premove_end = $move_from - 1;
      my $move_end = $move_from + $relocate_len - 1;
      my $postmove_start = $move_from + $relocate_len;
      my @premove = @ints[0..$premove_end];
      my @relocate_section = @ints[$move_from..$move_end];
      my @postmove;
      if( $postmove_start <= $#ints ) {
	@postmove = @ints[$postmove_start..$#ints];
      }
      #reassemble the ints w/o the moved section;
      @ints = (@premove,@postmove);
      my $preinsert_end = $move_to - 1;
      my @preinsert = @ints[0..$preinsert_end];
      my @postinsert;
      if( $move_to <= $#ints ) {
	@postinsert = @ints[$move_to..$#ints];
      }
      #now, put it all back together:
      @ints = (@preinsert,@relocate_section,@postinsert);
    }
    for my $i (1..$delete_count) {
      my $delete_location = int(rand($int_count-1));
      my @postdel = @ints[($delete_location+1)..$#ints];
      delete @ints[$delete_location..$#ints];
      push @ints, @postdel;
      #delete operation changes the number of integers
      $int_count = @ints + 0;
    }
    for my $i (1..$alter_count) {
      my $alter_location = int(rand($int_count));
      $ints[$alter_location] = int(rand(2**32));
    }
    for my $i (1..$insert_count) {
      my $insert_location = int(rand($int_count));
      my @postins = @ints[$insert_location..$#ints];
      delete @ints[$insert_location..$#ints];
      my $new = int(rand(2**32));
      push @ints, $new, @postins;
      #insert operation changes the number of integers
      $int_count = @ints + 0;
    }
    #mutation steps are done, so output altered data:
    print $out ( pack( "N*", @ints ) );
  }
  if( defined $remainderbuf ) {
    print $out ( $remainderbuf );
  }
  $in->close();
  $out->close();
}

=item cross_genomes( <in1>, <in2>, <out> [, min [, max [, exponent ] ] ] )

Performs a crossover operation, between <in1> and <in2>, and writes the result to <out>.  Crossover takes two sequences of 4 byte blocks, and outputs blocks alternating between the two sequences at crossover points.  The read position in the 'inactive' file is advanced at the same proportional (to the input file lengths) rate as in the 'active' file.  In the following illustration, blocks are represented by letters:

 <in1>:             AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
 <in2>:             BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB
 crossover points:      *   *      *     *    *      *  *
 <outfile>:         AAAABBBBAAAAAAABBBBBBAAAAABBBBBBBAAABBB

The parameters min, max, and exponent determine the distribution of segment lengths.  Min and max specify the bounds on segment length.  The actual length of each segment is found by taking a random number from 0 to 1 ( from rand() ), raising it to the power of the exponent, and scaling so that 0 becomes min, and 1 becomes max.  Higher values of exponent cause more short segments and fewer long segments.  The default values of min, max, and exponent are 20, 750, and 3, respectively.

=cut

sub cross_genomes {
  my $in1_filename = shift;
  my $in2_filename = shift;
  my $out_filename = shift;

  #cumulative chance of crossover
  my $min_cross = 20;
  my $max_cross = 750;
  my $cross_xpn = 3;

  if( @_ ) {
    $min_cross = shift;
  }
  if( @_ ) {
    $max_cross = shift;
  }
  if( @_ ) {
    $cross_xpn = shift;
  }
  # 0   1   2     3    4   5   6    7     8     9    10     11      12
  #dev ino mode nlink uid gid rdev size atime mtime ctime blksize blocks
  my @stat1 = stat($in1_filename);
  die "can't stat $in1_filename: $!" unless @stat1;
  my @stat2 = stat($in2_filename);
  die "can't stat $in2_filename: $!" unless @stat2;

  my $in1_size = $stat1[7];
  my $in2_size = $stat2[7];

  #open the input and output files,
  my $in1 = new IO::File( "<$in1_filename" )
    or die "Can't open source genome ($in1_filename): $!";
  my $in2 = new IO::File( "<$in2_filename" )
    or die "Can't open source genome ($in2_filename): $!";
  my $out = new IO::File( ">$out_filename" ) 
    or die "Can't open output ($out_filename): $!";

  my $immutable_len = NetCompiler::_genome_immutable_options_count() * 4;

  print $out ( read_bytes( $in1, $immutable_len ) );
  read_bytes( $in2, $immutable_len );

  _cross_the_streams( $in1, $in1_size, $in2, $in2_size, $out,
		      $min_cross, $max_cross, $cross_xpn );

  $in1->close();
  $in2->close();
  $out->close();
}

sub _cross_the_streams {
  my( $in1, $in1_size, $in2, $in2_size, $out,
      $min_cross, $max_cross, $cross_xpn ) = @_;

  #rand defaults to range of (0,1)
  #we want to allow large max crosses, but mostly do shorter ones
  my $cross_len = int( $min_cross + 
		       (1 - (rand())**$cross_xpn)*($max_cross - $min_cross) );

  #multiply lengths by 4, since we always work w/ 4 byte chunks
  my $n1 = $cross_len * 4;
  #length from 2nd file (discarded) is scaled by ratio of file sizes
  my $n2 = int($cross_len * ($in2/$in1)) * 4;

  my $bytes1 = read_bytes( $in1, $n1 );
  my $bytes2 = read_bytes( $in2, $n2 );
  if( (length( $bytes1 ) % 4) != 0 or
      (length( $bytes2 ) % 4) != 0 ) {
    die "data not read in 4 byte increments";
  }
  #data from file 1 goes to the output, data from file 2 is discarded
  print $out ( $bytes1 );
  if( $in1->eof() or $in2->eof() ) {
    my $remainder;
    if( $in1->eof() ) {
      $remainder = read_bytes( $in2, -1 );
    } else {
      $remainder = read_bytes( $in1, -1 );
    }
    if( (length( $remainder ) % 4) != 0 ) {
      die "data not read in 4 byte increments";
    }
    print $out ( $remainder );
    return;
  }
  else {
    #reverse the two files and repeat
    _cross_the_streams( $in2, $in2_size, $in1, $in1_size, $out,
			$min_cross, $max_cross, $cross_xpn );
  }
}

=item purge_introns( <infile>, <outfile> )

Reads through <infile>, using the start and end markers to keep track of whether the current block is part of a node definition, or not.  If it is, it is written to <outfile>.  All other (non-coding) blocks are discarded.

=cut

sub purge_introns {
  my $in_filename = shift;
  my $out_filename = shift;

  my $in = new IO::File( "<$in_filename" ) or die "Can't open source genome: $!";
  my $out = new IO::File( ">$out_filename" ) or die "Can't open output: $!";

  my $immutable_len = NetCompiler::_genome_immutable_options_count() * 4;
  print $out ( read_bytes( $in, $immutable_len ) );

  my $in_node = 0;
  while( not $in->eof() ) {
    my $buf = read_bytes( $in, 1024 * 4 );
    if( length( $buf ) % 4 != 0 ) {
      die "data not read in 4 byte increments";
    }
    my @ints = unpack( "N*", $buf );
    my @outs;
    my $node_start = 0;
    for my $i (0..$#ints) {
      if( $in_node and NetCompiler::_is_node_end( $ints[$i] ) ) {
	push @outs, @ints[$node_start..$i];
	$in_node = 0;
      }
      elsif( not $in_node and NetCompiler::_is_node_start( $ints[$i] ) ) {
	$node_start = $i;
	$in_node = 1;
      }
    }
    if( $in_node ) {
      push @outs, @ints[$node_start..$#ints];
    }
    print $out ( pack( "N*", @outs ) );
  }

  close $in;
  close $out;
}

#nbytes = -1 means read all remaining.
sub read_bytes {
  my $in = shift;
  my $nbytes = shift;
  #this needs to be a whole number or we get caught in an infinite loop
  $nbytes = int($nbytes);

  my $buf;
  my $nread = 0;
  my $bytes = "";

  while( not $in->eof() and ( $nread < $nbytes or $nbytes == -1 ) ) {
    my $readlen =  (($nbytes > 0)?($nbytes - $nread):1024);
    my $len = $in->read( $buf, $readlen );
    if( not defined $len ) {
      die "error reading from file: $!";
    }
    $nread += $len;
    $bytes .= $buf;
  }
  return $bytes;
}


1;
#end

=back

=cut
