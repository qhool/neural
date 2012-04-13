package NetCompiler::Genome;

sub __compile_net {
  my $net = shift;
  my %opt = @_;
  my @intarray;

  #first, the options:
  push @intarray, ( $net->opt( 'inputs' ),
		    $net->opt( 'outputs' )
		  );

  my @nodes;
  my @inputs = $net->_input_ids();
  my @outputs = $net->_output_ids();
  {
    my @all_nodes = $net->_list_raw_nodes();
    #add only nodes which are not inputs or outputs to the main nodes list
    for my $id (@all_nodes) {
      my $ok = 1;
      for my $inp (@inputs) {
	if( $id eq $inp ) {
	  $ok = 0;
	  last;
	}
      }
      for my $outp (@outputs) {
	if( $id eq $outp ) {
	  $ok = 0;
	  last;
	}
      }
      if( $ok ) {
	push @nodes, $id;
      }
    }
  }
  #outputs come last:
  push @nodes, @outputs;
  #assign a numerical id to all nodes:
  my %id_map;
  my $num = 0;
  #inputs come first
  for my $inp (@inputs) {
    $id_map{$inp} = $num;
    $num++;
  }
  for my $id (@nodes) {
    $id_map{$id} = $num;
    $num++;
  }

  #now output the nodes
  for my $id (@nodes) {
    #add intron, if selected
    if( exists( $opt{introns} ) ) {
      my $intron_len = int( rand( $opt{introns}->{max} ) )+ $opt{introns}->{min};
      for my $i (1..$intron_len) {
	my $rval;
	#node start markers are the only forbidden items in introns
	do {
	  $rval = rand( 2**32 );
	} while( NetCompiler::_is_node_start( $rval ) );
	push @intarray, $rval;
      }
    }
    #insert the node start marker:
    push @intarray, 62 << 25;
    my %ins = $net->_list_raw_node_ins_weighted( $id );
    while( my( $in, $weight ) = each( %ins ) ) {
      $weight = encode_weight( $weight );
      push @intarray, ( $weight << 16 ) +  $id_map{$in};
    }
    #add the end marker:
    push @intarray, 63 << 25;
  }

  #print "\n@intarray\n";

  return pack( "N*", @intarray );
}

sub encode_weight {
  my $weight = shift;
  #random weight (undef value) must be represented as a value
  #not divisible by 4
  unless( defined $weight ) {
    $weight = 1;
  } else {
    #we want to convert the floating point to a special 14 bit representation:
    my $exp_sign = (abs($weight) > 1)?1:-1;
    if( abs($weight) > 500 ) {
      $weight = ($weight > 0)?500:-500;
    }
    my $exp = 0;
    while( -7 < $exp and $exp < 8 ) {
      if( 0.5 <= abs($weight) and abs($weight) <= 2 ) {
	last;
      }
      $exp += $exp_sign;
      $weight /= 2**$exp_sign;
    }
    # +---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+
    # | F | E | D | C | B | A | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
    # +---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+
    # |               MANTISSA                |    EXPONENT   | 0mod4 |
    # +---------------------------------------+---------------+-------+
    my $mant = $weight * 2**8 + 2**9 - 1;
    $exp += 7;
    $weight = ($mant << 6) + ($exp << 2);
  }
  return $weight;
}

sub decode_weight {
  my $weight = shift;
  if( ($weight % 4) != 0 ) {
    #random weight represented as not-defined
    $weight = undef;
  } else {
    $weight = $weight >> 2;
    #2 lsb are 0, so we have 14 bits left,
    #use 4 for the mantissa, and 10 for exponent:
    my $mant = $weight >> 4;
    my $exp = $weight % 2**4;
    $mant = ($mant - 2**9 + 1) / 2**8;
    $exp = $exp - 7;
    $weight = $mant * (2**$exp);
  }
  return $weight;
}


1;
#end
