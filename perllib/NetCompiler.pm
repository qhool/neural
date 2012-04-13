=head1 NAME

NetCompiler - analyze computational (neural) networks and compile them to C

=head1 SYNOPSIS

 use NetCompiler;
 $netcompiler = NetCompiler->new( filename => 'foo.net' );
 $netcompiler->compile( 'c', 'foo.c' );

=head1 DESCRIPTION

NetCompiler is intended to automatically produce C code to execute and train neural networks.  It takes as input a specification in one of two formats (see L</FORMATS>); one for humans, one for use in genetic algorithms.  It can compile from either of these formats to C code (the primary use) and to input files to graphviz for production of pictures of the network.  It cannot recover the input formats from C or graphviz output.  See the L</EXTENDING> section for information about extending NetCompiler to handle other formats.

=head1 INTERFACE

=over

=cut

package NetCompiler;

use Data::Dumper;
use IO::File;
use Carp qw(cluck);

use Errorable;
use NetCompiler::GraphViz;
use NetCompiler::Genome;
use NetCompiler::C;

BEGIN {
  @NetCompiler::ISA = qw(Errorable);
}

=item $netcompiler = NetCompiler->new( <option> => <value> [, ...] )

Creates a new instance of NetCompiler. You must specify either the 'filename' option or the 'data' option.

=head4 available options

=over

=item filename

Filename to read network definition from.

=item data

Scalar or reference of memory structure to read definition from

=item genome_mode

If set to a true value, input is interpreted as a network genome. (see L</FORMATS>)

=back

=cut

#we use Errorable's new() which calls _init()
sub _init {
  my $self = shift;
  $self = $self->SUPER::_init(@_);
  if( defined $self ) {
    $self->_clear_input_ids();
    $self->_clear_output_ids();
    my %options = %{$_[0]};
    if( defined $options{genome_mode} ) {
      $self->{_READ_INTS} = 1;
    }
    if( defined $options{filename} ) {
      $self->_input_file( $options{filename} );
    }
    elsif( defined $options{data} ) {
      $self->_input_buffer( $options{data} );
    } else {
      return undef;
    }
    if( defined $options{genome_mode} ) {
      $self->_load_genome();
    } else {
      $self->_load_hreadable();
    }
    $self->_analyse_raw_net();
    $self->_close_input();
    return $self;
  } else {
    return undef;
  }
}

=item $netcompiler->compile( <type> [, <output_file>] )

Compiles/translates the network loaded with new() into <type>, which must be one of "graphviz","genome", or "c".  If <output_file> is specified, writes compiled network to that file.  Returns the compiled network.

=cut

sub compile {
  my $self = shift;
  my $type = shift;
  my %options = @_;

  my $filename = $options{filename};

  my $output;
  if( $type eq 'graphviz' ) {
    $output = NetCompiler::GraphViz::__compile_net( $self, %options );
  } elsif( $type eq 'genome' ) {
    $output = NetCompiler::Genome::__compile_net( $self, %options );
  } elsif( $type eq 'c' ) {
    $output = NetCompiler::C::__compile_net( $self, %options );
  }
  if( defined $filename and defined $output ) {
    $self->debug( 1,  "Compiled net is ", length($output), 
	   " bytes -- writing to $filename\n" );
    open COMP, ">$filename" or die "Can't open $filename for output: $!";
    print COMP $output;
    close COMP;
    return 1;
  }
  return $output;
}

=back

=head1 FORMATS

The input formats for networks are described in greater detail in the docs/ directory.

=head2 Human Readable Format

The human editable format is just a file containing a Perl data structure.  It should be an anonymous hash with two entries: OPTIONS and LAYERS, each of which should be a hash ref, with the keys in LAYERS each being a layer name, and the values being arrays of nodes.  Each node is an array of input specifiers, and each input specifier is a two element array, where the first element is the name of the node to receive input from, and the second element is the starting weight, or 'R' for random starting weight.

Here is a sample network in this format:

 { OPTIONS => { INPUTS => 2,
                OUTPUTS => 1 },
   LAYERS => { A => [ [ ["IN1", 'R'], ["IN2", 'R'] ],
                      [ ["IN1", 'R'], ["IN2", 'R'] ],
                    ],
               OUT => [ [ ["A1", 'R'], ["A2", 'R'] ],
                      ],
             }
 }

=head1 EXTENDING

Extending NetCompiler to have additional output formats is fairly simple.  You must create a sub in a separate module which can be passed a reference to the netcompiler object, and an (optional) options hash.  There is no formal extension loading mechanism, you must edit the 'compile' sub in NetCompiler.pm, and place the call to your new sub in the if.. elsif.. sequence there.  

Extending NetCompiler to new input formats is beyond the scope of this manual.  You should become familiar with the source of NetCompiler.pm before attempting this.

Below is documentation of the NetCompiler methods useful for output format modules:

=over

=cut

########################################
#                                      #
#   file/buffer IO abstraction layer   #
#                                      #
########################################

sub _input_file {
  my $self = shift;
  my $filename = shift;

  $self->debug( 1, "opening $filename\n" );

  my $fh = new IO::File( "<$filename" );

  if( defined $fh ) {
    if( $self->{_READ_INTS} ) {
      $self->{_INPUT_READER} =
	sub { my $num = 1;
	      if( @_ ) { $num = shift; }
	      my $dat;
	      $fh->read( $dat, $num * 4 );
	      if( defined $dat ) {
		my @ret = unpack( "N*", $dat );
		if( $num == 1 ) {
		  #print " $ret[0] ";
		  return $ret[0];
		} else {
		  return @ret;
		}
	      } else {
		return undef;
	      }
	    };
    } else {
      $self->{_INPUT_READER} =
	sub { if( @_ ) { my $buf; return $fh->read( $buf, $_[0] ); } 
	      else { return <$fh>; } };
    }
    $self->{_INPUT_REWIND} =
      sub { $fh->seek( 0, 0 ) };
    $self->{_INPUT_CLOSE} =
      sub { $fh->close() };
  } else {
    return undef;
  }
}

sub _input_buffer {
  my $self = shift;
  my $buffer = shift;
  $self->{_BUFFER} = $buffer;
  my $buffer_position = 0;
  if( ref( $buffer ) ) {
    if( ref( $buffer ) eq 'ARRAY' ) {
      $self->{_INPUT_READER} =
	sub { my $len = 1; 
	      if( @_ ) { $len = shift; }
	      return undef if $buffer_position > $#$buffer;
	      my $oldpos = $buffer_position;
	      $buffer_position += $len;
	      return $buffer->[$oldpos..$buffer_position];
	    };
    } else {
      $self->{_INPUT_READER} =
	sub { return _rdstr($buffer, \$buffer_position, $self->{_READ_INTS}, @_) };
    }
  }
  else {
    $self->{_INPUT_READER} =
      sub { return _rdstr(\$buffer, \$buffer_position, $self->{_READ_INTS}, @_) };
  }
  $self->{_INPUT_REWIND} = sub { $buffer_position = 0 };
  $self->{_INPUT_CLOSE} = sub { $buffer = undef };
  return 1;
}

sub _rdstr {
  my $stref = shift;
  my $posref = shift;
  my $rdlines = shift;
  my $len = undef;
  if( @_ ) {
    $len = shift;
  }
  my $strlen = length( $str );
  if( $pos >= $strlen ) {
    return undef;
  }
  if( not defined( $len ) or $rdlines ) {
    my $n = 0;
    my $pos = $$posref;
    while( $n < $len ) {
      my $idx = index( $$stref, "\n", $pos );
      if( $idx == -1 ) {
	$pos = $strlen;
	last;
      } else {
	$pos = $idx;
      }
    }
    $len = $pos - $$posref;
  }
  my $oldpos = $$posref;
  $$posref += $len;
  return substr( $$stref, $oldpos, $len );
}


#if a parameter is given it is the number of bytes/integers to read
#otherwise, either one integer (if the input is an array), or one line is 
sub _read_input {
  my $self = shift;
  return &{$self->{_INPUT_READER}}(@_);
}

sub _rewind_input {
  my $self = shift;
  return &{$self->{_INPUT_REWIND}}(@_);
}

sub _close_input {
  my $self = shift;
  return &{$self->{_INPUT_CLOSE}}(@_);
}

##################################################
#                                                #
#          Raw Node & Option handling            #
#       setup by format specific loaders         #
#                                                #
##################################################


#parameter is raw node expressed as list
#  ( 'ID', [ 'ID', <weight> ], [ 'ID', <weight> ] )
sub _add_raw_node {
  my $self = shift;

  unless( defined $self->{_RAW_NODES} ) {
    $self->{_RAW_NODES} = {};
  }

  my $node = {};
  $node->{IN} = [];
  $node->{ID} = shift;
  $self->debug( 2, "Adding node $node->{ID}: " );

  for my $con (@_) {
    push @{$node->{IN}}, { ID => $con->[0],
			   WEIGHT => $con->[1] };
    if( defined $con->[0] and defined $con->[1] ) {
      $self->debug( 3, " $con->[0] ( $con->[1] ) " );
    }
  }
  $self->debug( 2, "\n" );
  $self->{_RAW_NODES}->{$node->{ID}} = $node;
  return $node;
}

#these should *not* correspond to any raw nodes
sub _add_input_ids {
  my $self = shift;
  push @{$self->{_INPUT_IDS}}, @_;
}

sub _clear_input_ids {
  my $self = shift;
  $self->{_INPUT_IDS} = [];
}

=item $netcompiler->_input_ids

Returns a list of the IDs of the input nodes.

=cut

sub _input_ids {
  my $self = shift;
  return @{$self->{_INPUT_IDS}};
}

#these *must* correspond to raw nodes
sub _add_output_ids {
  my $self = shift;
  push @{$self->{_OUTPUT_IDS}}, @_;
}

sub _clear_output_ids {
  my $self = shift;
  $self->{_OUTPUT_IDS} = [];
}

=item $netcompiler->_output_ids

Returns a list of the IDs of the output nodes.

=cut

sub _output_ids {
  my $self = shift;
  return @{$self->{_OUTPUT_IDS}};
}

sub _raw_node_count {
  my $self = shift;

  unless( defined $self->{_RAW_NODES} ) {
    return 0;
  } else {
    return (0 + keys( %{$self->{_RAW_NODES}}));
  }
}

sub _get_raw_node {
  my $self = shift;
  my $id = shift;
  if( defined $id ) {
    return $self->{_RAW_NODES}->{$id};
  } else {
    cluck "undef ID";
    return undef;
  }
}

=item $netcompiler->_list_raw_nodes

Returns a list of all node IDs.

=cut

sub _list_raw_nodes {
  my $self = shift;
  return keys( %{$self->{_RAW_NODES}} );
}

=item $netcompiler->_list_raw_node_ins( <id> )

Returns a list of the IDs of all nodes from which the node with ID <id> receives input.

=cut 

sub _list_raw_node_ins {
  my $self = shift;
  my $id = shift;
  my $node = $self->_get_raw_node( $id );
  my @ret;
  for my $in (@{$node->{IN}}) {
    push @ret, $in->{ID};
  }
  return @ret;
}

=item $netcompiler->_list_raw_node_ins_weighted( <id> )

Returns a list of the inputs for node <id>, with entries of the form: { ID => <input_id>, WEIGHT => <weight> }.

=cut

sub _list_raw_node_ins_weighted {
  my $self = shift;
  my $id = shift;
  my $node = $self->_get_raw_node( $id );
  my %ret;
  for my $in (@{$node->{IN}}) {
    $ret{$in->{ID}} = $in->{WEIGHT};
  }
  return %ret;
}

sub _add_raw_node_outs {
  my $self = shift;
  my $id = shift;
  $self->debug( 5, "Adding out to $id: @_\n" );
  my $node = $self->_get_raw_node( $id );
  if( not exists $node->{OUT} ) {
    $node->{OUT} = [];
  }
  push @{$node->{OUT}}, @_;
}

=item $netcompiler->_list_raw_node_outs( <id> )

Returns a list of the node IDs which receive input from node <id>.

=cut

sub _list_raw_node_outs {
  my $self = shift;
  my $id = shift;
  my $node = $self->_get_raw_node( $id );
  if( defined( $node->{OUT} ) ) {
    return @{$node->{OUT}};
  } else {
    return ();
  }
}

sub __taint {
  my $self = shift;
  my $taintname = shift;
  my $id = shift;
  my $node = $self->_get_raw_node( $id );
  if( @_ ) {
    $self->debug( 5, "$id($_[0]) " );
    $node->{$taintname . "_TAINT"} = shift;
  }
  return $node->{$taintname . "_TAINT"};
}

sub __list_taints {
  my $self = shift;
  my $id = shift;
  my $node = $self->_get_raw_node( $id );
  my %taints;
  while( my($key, $val) = each( %$node ) ) {
    if( $key =~ /^(.*)_TAINT$/ ) {
      $taints{$1} = $val;
    }
  }
  return %taints;
}

sub _feed_taint {
  my $self = shift;
  my $num = shift;
  return $self->__taint( "FEED_$num", @_ );
}

=item $netcompiler->_list_feed_taints( <$id> )

Returns a list of the feedback group numbers from which the node <id> receives input.

=cut

sub _list_feed_taints {
  my $self = shift;
  my $id = shift;
  my @ret;
  my %taints = $self->__list_taints( $id );
  while( my( $k, $v ) = each( %taints ) ) {
    if( $k =~ /^FEED_(.*)$/ ) {
      push @ret, $1;
    }
  }
  return @ret;
}

=item $netcompiler->_<taint_type>_taint( <id> )

Each of the taint functions returns a true value if the node <id> is marked with that taint type.  The possible taint types are:

=over

=cut

sub _back_taint {
  my $self = shift;
  return $self->__taint( "BACK", @_ );
}

=item _input_taint

Receives (in)direct input from an input node.

=cut

sub _input_taint {
  my $self = shift;
  return $self->__taint( "INPUT", @_ );
}

=item _output_taint

Output from node is (in)directly received by an output node.

=cut

sub _output_taint {
  my $self = shift;
  return $self->__taint( "OUTPUT", @_ );
}

=item _disconnect_taint

Node does not get input from network inputs, or does not send output to network outputs.

=cut

sub _disconnect_taint {
  my $self = shift;
  return $self->__taint( "DISCONNECT", @_ );
}

=item _precalc_taint

Node may be computed before any feedback portions of network.

=cut

sub _precalc_taint {
  my $self = shift;
  return $self->__taint( "PRECALC", @_ );
}

=item _feedback_taint

Node is part of a feedback loop.

=cut

sub _feedback_taint {
  my $self = shift;
  return $self->__taint( "FEEDBACK", @_ );
}

=item _postcalc_taint

Node is not a feedback node, but must be computed after some feedback nodes.

=cut

sub _postcalc_taint {
  my $self = shift;
  return $self->__taint( "POSTCALC", @_ );
}

=back

=item $netcompiler->_calc_order( <id> )

Returns an integer giving the compute order of the node.  Nodes must be computed in ascending order.  Nodes with the same compute order are either part of the same feedback loop, or may be computed in parallel.

=cut

sub _calc_order {
  my $self = shift;
  return $self->__taint( "CALC_ORDER", @_ );
}

=item $netcompiler->_node_taint( <id>, <tainted_by_id> )

Returns true if node <id> receives (in)direct output from <tainted_by_id>.

=cut

sub _node_taint {
  my $self = shift;
  my $taint_id = shift;
  return $self->__taint( "NODE_" . $taint_id, @_ );
}

=item $netcompiler->_list_node_taints( <id> )

Returns a list of all node IDs from which the node <id> receives direct/indirect input.

=cut

sub _list_node_taints {
  my $self = shift;
  my $id = shift;
  my @ret;
  my %taints = $self->__list_taints( $id );
  while( my( $k, $v ) = each( %taints ) ) {
    if( $k =~ /^NODE_(.*)$/ ) {
      push @ret, $1;
    }
  }
  return @ret;
}

sub _layer {
  my $self = shift;
  my $layer = shift;
  return @{$self->{_LAYERS}->[$layer]};
}

=item $netcompiler->_calc_groups

Returns a list of simultaneously calculable node groupings, in compute order.  Each item in the list is a reference to an array of the nodes in the grouping, except for feedback groups, which have all their nodes grouped together in a single sub-array within the compute group.

=cut

sub _calc_groups {
  my $self = shift;
  if( @_ ) {
    @{$self->{_CALC_GROUPS}} = @_;
  }
  return @{$self->{_CALC_GROUPS}};
}

sub _generate_random_weight {
  my $self = shift;
  #get a rand # between 0 and 2^16:
  return int(rand(2**16));
}

my %opt_keys = ( INPUTS => '_INPUT_COUNT',
		 OUTPUTS => '_OUTPUT_COUNT',
	       );

=item $netcompiler->opt( 'optname' )

Returns the value of the network option specified by 'optname'.  Current option names are 'inputs' and 'outputs', for the number of each in the network.

=cut

sub opt {
  my $self = shift;
  my $optname = shift;
  my $key = $opt_keys{uc($optname)};
  if( defined $key ) {
    if( @_ ) {
      $self->debug( 2, "Set opt $optname: $_[0]\n" );
      $self->{$key} = shift;
    }
    return $self->{$key};
  }
  die "Unknown option: '$optname'"
}

########################
#                      #
#   Network Analysis   #
#                      #
########################

sub _analyse_raw_net {
  my $self = shift;
  my $net_ok = 1;

  #first, add raw nodes for input:
  my @input_nodes;
  my @input_ids = $self->_input_ids();
  my @output_ids = $self->_output_ids();
  for my $id (@input_ids) {
    push @input_nodes, $self->_add_raw_node( $id );
  }
  #next, go through all raw nodes, and mark outputs.
  $self->debug( 2, "Marking outputs\n" );
  my @all_nodes = $self->_list_raw_nodes();
  for my $id (@all_nodes) {
    my @ins = $self->_list_raw_node_ins( $id );
    if( @ins ) {
      $self->debug( 3, "@ins }---> $id\n" );
    }
    for my $in (@ins) {
      $self->_add_raw_node_outs( $in, $id );
    }
  }

  #propagate taints:
  #input_taint:
  $self->debug( 3, "\nINPUT_TAINT: " );
  $self->{_LAYERS} = [ $self->_propagate_taint( sub { $self->_input_taint( @_ ) },
						'forward', 1, @input_ids ) ];
  #output_taint:
  $self->debug( 3, "\nOUTPUT_TAINT: " );
  $self->_propagate_taint( sub { $self->_output_taint( @_ ) },
			   'backward', 1, @output_ids );

  #once we've computed output taints, sort all_nodes list by it (descending):
  #this puts them in an approximation of compute order 
  @all_nodes = sort { $self->_output_taint( $b ) <=> $self->_output_taint( $a ) }
    @all_nodes;

  $self->debug( 2, "\n\nCompute order: @all_nodes\n\n" );

  #Check for network problems
  $self->debug( 2, "Checking connectivity... " );
  my $all_io = 1;
  for my $id (@all_nodes) {
    unless( $self->_input_taint( $id ) and
	    $self->_output_taint( $id ) ) {
      if( $all_io ) {
	$self->debug( 3, "\n\tThese nodes do not receive input / provide output:\n\t");
	$all_io = 0;
      }
      $self->debug( 3, "$id " );
      $self->_disconnect_taint( $id, 1 );
    }
  }
  if( $all_io ) {
    $self->debug( 2, "all ok" );
  }
  $self->debug( 2, "\n" );
  #check to make sure all inputs feed to outputs:
  my $input_output = 1;
  for my $id (@input_ids,@output_ids) {
    if ( $self->_disconnect_taint( $id ) ) {
      $input_output = 0;
    }
  }
  unless( $input_output ) {
    $self->debug( 1, "  **************************************\n" );
    $self->debug( 1, "  Some inputs/outputs are not connected.\n" );
    $self->debug( 1, "  **************************************\n\n" );
    $net_ok = 0;
  }
  #propagate taints for all nodes - this determines feedback:
  $self->debug( 2, "Determining node taints.\n" );
  my @feedback_nodes;
  my @non_feedback_nodes;
  for my $id (@all_nodes) {
    $self->debug( 3, "$id: " );
    my @outs = $self->_list_raw_node_outs( $id );
    #don't simply use the node itself as the starting layer, b/c
    #the main point is really to see whether the node eventually 
    #gets input from itself
    $self->_propagate_taint( sub { $self->_node_taint( $id, @_ ) },
			     'forward', 1, @outs );
    if( $self->_node_taint( $id, $id ) ) {
      $self->_feedback_taint( $id, 1 );
      push @feedback_nodes, $id;
      $self->debug( 3, " --feedback--!!" );
    } else {
      push @non_feedback_nodes, $id;
    }
    $self->debug( 2, "\n" );
  }

  my $fb_set = 2;
  my @feedback_groups;
  for my $id (@all_nodes) {
    if( defined( $self->_feedback_taint( $id ) ) and
	$self->_feedback_taint( $id ) < 2 ) {
      my @inp_from = $self->_list_node_taints( $id );

      $self->debug( 3, "FEEDBACK group ", $fb_set -1, ": " );
      for my $inp (@inp_from) {
	#if $inp is a feedback node, and it receives input from the current
	#node, they are both in the same feedback class
	if( $self->_feedback_taint( $inp ) and
	    $self->_node_taint( $id, $inp ) ) {
	  push @{$feedback_groups[$fb_set - 2]}, $inp;
	  $self->_feedback_taint( $inp, $fb_set );
	  $self->debug( 3, "$inp " );
	}
      }
      $self->debug( 3, "\n" );
      $fb_set++;
    }
  }
  #feedback sets start at 2, shift numbers down one:
  for my $id (@all_nodes) {
    my $fbt = $self->_feedback_taint( $id );
    if( $fbt ) {
      $self->_feedback_taint( $id, $fbt - 1 );
    }
  }

  #feed taint:
  $self->debug( 2, "\n" );
  for my $fb_group (@feedback_groups) {
    my $fb_num = $self->_feedback_taint( $fb_group->[0] );
    $self->debug( 3, "FEED_TAINT group $fb_num: " );
    $self->_propagate_taint( sub { $self->_feed_taint( $fb_num, @_ ) }, #taint func
			     'forward', 1, @$fb_group );
    $self->debug( 3, "\n" );
  }
  #find the pre and post feedback nodes
  my $pre = "";
  my $post = "";
  $self->debug( 1, "Partitioning network" );
  for my $id (@all_nodes) {
    my $fb = $self->_feedback_taint( $id );
    my @f = $self->_list_feed_taints( $id );
    if( not @f and not $fb ) {
      $self->_precalc_taint( $id, 1 );
      $pre .= "$id ";
      $self->debug( 2, "." );
    }
    elsif( not $fb ) { #no actual feedback
      $self->_postcalc_taint( $id, 1 );
      $post .= "$id ";
      $self->debug( 2, ":" );
    }
    else {
      $self->debug( 2, "o" );
    }
  }
  $self->debug( 1, "\nNodes computed before feedback:\n\t$pre\n" );
  $self->debug( 1, "Feedback portion of net:\n\t@feedback_nodes\n" );
  $self->debug( 1, "Nodes computed after feedback:\n\t$post\n" );

  $self->debug( 1, "Sorting network\n" );

  my @comp_order = @non_feedback_nodes;

  #we want to sort each feedback group as a unit, so just include 1 representative
  for my $grp (@feedback_groups) {
    push @comp_order, $grp->[0];
  }

  @comp_order = sort( { $self->_node_compute_dependency( $a, $b ) } @comp_order );
  $self->debug( 2, "@comp_order \n" );
  my @comp_groups;
  my $last_id = undef;
  my $comp_group = -1;
  my $nocomp = 0;
  for my $id (@comp_order) {
    if( $self->_node_compute_dependency( $last_id, $id ) != 0 ) {
      $comp_group++;
      unless( $self->_disconnect_taint( $id ) ) {
	$self->debug( 2, "\nCompute Group $comp_group: " );
      } else {
	$self->debug( 2, "\nNot Computed $comp_group: " );
	$nocomp = 1;
	$comp_group = -1;
      }
    }
    my $fbt = $self->_feedback_taint( $id );
    if( $fbt ) {
      my $fb_group = $feedback_groups[$fbt - 1];
      $self->debug( 2, " ( " );
      for my $f_id (@$fb_group) {
        $self->debug( 2, "$f_id " );
	$self->_calc_order( $f_id, $comp_group );
      }
      $self->debug( 2, ") " );
      unless( $nocomp ) {
	push @{$comp_groups[$comp_group]}, $fb_group;
      }
    } else {
      $self->debug( 2, " $id " );
      unless( $nocomp ) {
	push @{$comp_groups[$comp_group]}, $id;
      }
      $self->_calc_order( $id, $comp_group );
    }
    $last_id = $id;
  }
  $self->_calc_groups( @comp_groups );
    
  $self->debug( 1, "\n----Analysis Complete----\n" );
  return 1;
}

sub _propagate_taint {
  my $self = shift;
  my $taint_fn = shift;
  my $fwd = shift;
  my $level = shift;
  my $forward;
  if( $fwd eq 'forward' ) {
    $forward = 1;
  } else {
    $forward = 0;
  }
  my @start_nodes = @_;
  my @nodes;
  my @next_nodes;
  for my $id (@start_nodes) {
    next if &$taint_fn( $id );
    &$taint_fn( $id, $level );
    $self->debug( 3, "$id " );
    push @nodes, $id;
    my @conns;
    if( $forward ) {
      @conns = $self->_list_raw_node_outs( $id );
    } else {
      @conns = $self->_list_raw_node_ins( $id );
    }
    for my $conn (@conns) {
      push @next_nodes, $conn;
    }
  }
  my @layers;
  if( @next_nodes ) {
    @layers = $self->_propagate_taint( $taint_fn, $fwd, $level +1, @next_nodes );
  }
  unshift @layers, \@nodes;
  return @layers;
}

#takes two node ids (a & b), returns:
# 1 if b should be computed 1st
# -1 if a should be computed 1st
# 0 if they can be calculated in parallel
# -----
# should not be given two nodes in the same feedback group
sub _node_compute_dependency {
  my $self = shift;
  my( $id_a, $id_b ) = @_;

  return -1 if not defined $id_a or not defined $id_b;

  #b depends on a
  if( $self->_disconnect_taint( $id_a ) and
      $self->_disconnect_taint( $id_b ) ) {
    $self->debug( 4, "X" );
    return 0;
  }
  elsif( $self->_disconnect_taint( $id_a ) ) {
    $self->debug( 4, '\\' );
    return 1;
  } elsif( $self->_disconnect_taint( $id_b ) ) {
    $self->debug( 4, "/" );
    return -1;
  }
  elsif( $self->_node_taint( $id_a, $id_b ) ) {
    $self->debug( 4, "<" );
    return -1;
  } #a depends on b
  elsif ( $self->_node_taint( $id_b, $id_a ) ) {
    $self->debug( 4, ">" );
    return 1;
  } else {
    $self->debug( 4, "=" );
    return 0;
  }
}

###############################
#                             #
#   Format specific loaders   #
#                             #
###############################

#################
# Genome loader #
#################

sub _load_genome {
  my $self = shift;

  #process the network-wide options at the head of the genome file.
  my $genome_opt_len = $self->_load_genome_options();

  my $node_count = $self->_load_genome_count_nodes( $genome_opt_len );
  $self->debug( 1, "$node_count nodes\n" );

  #the inputs are just the first input_count node ids
  $self->_add_input_ids( (0..($self->opt( 'inputs' ) - 1)) );
  #last output_count node ids are the outputs
  my $lastnum = $node_count + $self->opt( 'inputs' );
  $self->_add_output_ids( (($lastnum - $self->opt('outputs'))..($lastnum - 1)) );

  while( $self->_load_genome_intron() ) {
    $self->_load_genome_node( $lastnum );
  }
}

sub _genome_immutable_options_count {
  return 2;
}

sub _load_genome_options {
  my $self = shift;
  #remember to add the same stuff in Genome.pm
  $self->opt( 'inputs', $self->_read_input() );
  $self->opt( 'outputs', $self->_read_input() );
  return 2;
}

sub _load_genome_count_nodes {
  my $self = shift;
  my $opt_len = shift;
  my $count = 0;
  my $in_node = 0;
  while( my $i = $self->_read_input() ) {
    if( not $in_node and _is_node_start( $i ) ) {
      $in_node = 1;
      $count++;
    }
    elsif( $in_node and _is_node_end( $i ) ) {
      $in_node = 0;
    }
  }
  $self->_rewind_input();
  $self->_read_input( $opt_len );
  return $count;
}

sub _is_node_start {
  my $n = shift;
  return (($n>>25) == 62)?1:0;
}

sub _is_node_end {
  my $n = shift;
  return (($n>>25) == 63)?1:0;
}

sub _load_genome_intron {
  my $self = shift;
  my $ret = 0;
  my $intronlen = 0;
  while( my $i = $self->_read_input() ) {
    if( _is_node_start( $i ) ) {
      $ret = 1;
      $self->debug( 3, "Intron had length $intronlen\n" );
      last;
    }
    $intronlen++;
  }
  return $ret;
}

sub _load_genome_node {
  my $self = shift;
  my $node_count = shift;

  my $num = $self->_raw_node_count() + $self->{_INPUT_COUNT};

  my @conns;
  #each connection is represented in the 4 byte integer value
  #the first 2 (most significant) bytes are the connection weight
  #the 2nd 2 are the connected node
  CONN: while( my $i = $self->_read_input() ) {
      if( _is_node_end( $i ) ) {
	$self->debug( 4, "Node end\n" );
	last CONN;
      }
      $self->debug( 4, "raw connection: $i -- " );
      my $weight = NetCompiler::Genome::decode_weight( $i>>16 );
      if( defined $weight ) {
	$self->debug( 4, "wght: $weight " );
      }
      #we want the connected node to be a node found in the network
      #so drop high bits until it is
      my $con = $i % 2**16;
      $self->debug( 4, "rawcon: $con\n" );
      my $pwr = 15;
      while( $con >= $node_count ) {
	$con = $i % (2**$pwr);
	$pwr--;
      }
      push @conns, [ $con, $weight ];
    }
  $self->_add_raw_node( $num, @conns );
  return $num;
}

################################
# human friendly format loader #
################################

sub _load_hreadable {
  my $self = shift;

  my $code = "";
  while( my $line = $self->_read_input() ) {
    $code .= $line;
  }
  my $in = eval( $code );
  #print Data::Dumper::Dumper( $in );

  #handle options
  while( my( $opt, $val ) = each( %{$in->{OPTIONS}} ) ) {
    $self->opt( $opt, $val );
  }
  #setup input designations - output nodes added below
  my @ins = ( map { "IN" . $_ } (1..$self->opt( 'inputs' )) );
  $self->_add_input_ids( @ins );
  #load nodes
  while( my($layer, $nodelist) = each( %{$in->{LAYERS}} ) ) {
    next if $layer eq 'IN';
    my $num = 0;
    for my $node (@$nodelist) {
      $num++;
      my $name = $layer . $num;
      my @conns;
      for my $input (@$node) {
	my $input_id = $input->[0];
	my $weight = $input->[1];
	if( $weight eq 'R' ) {
	  #random weight is undef
	  $weight = undef;
	}
	push @conns, [ $input_id, $weight ];
      }
      if( $layer eq 'OUT' ) {
	#note that this is an output node
	$self->_add_output_ids( $name );
      }
      $self->_add_raw_node( $name, @conns );
    }
  }
}

=back

=cut


1;

