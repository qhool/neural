package NetCompiler::C;

use Template;

sub __compile_net {
  my $net = shift;
  my %opt = @_;

  my $weight_idx = 0;
  my @calc_groups = $net->_calc_groups();

  my @all;
  my @calc_sets;
  my %weight_idx_table;
  my $i = 0;
  my $set_start = 1;
  my $prev_fb = 0;
  for my $calc_grp (@calc_groups) {
    for my $x (@$calc_grp) {
      if( ref( $x ) eq 'ARRAY' ) {
	push @all, @$x;
	unless( $set_start ) {
	  $i++;
	}
	$calc_sets[$i] = { feedback => 1, nodes => [] };
	for my $id (@$x) {
	  push @{$calc_sets[$i]->{nodes}}, _node_with_inputs( $net, $id,
							      \$weight_idx,
							      \%weight_idx_table );
	}
	$set_start = 0;
	$pref_fb = 1;
      } else {
	push @all, $x;
	if( $prev_fb ) {
	  $i++;
	  $prev_fb = 0;
	  $set_start = 1;
	}
	if( $set_start ) {
	  $calc_sets[$i] = { feedback => 0, nodes => [] };
	  $set_start = 0;
	}
	push @{$calc_sets[$i]->{nodes}}, _node_with_inputs( $net, $x,
							    \$weight_idx,
							    \%weight_idx_table );
      }
    }
    $i++;
    $prev_fb = 0;
    $set_start = 1;
  }
  #print "Weight idx table:\n", Data::Dumper::Dumper( \%weight_idx_table );

  #now we have to go through and set the weight index for all outputs:
  for my $set (@calc_sets) {
    for my $node (@{$set->{nodes}}) {
      for my $out (@{$node->{out}}) {
	$out->{weight_index} = $weight_idx_table{$out->{id}}->{$node->{id}};
      }
    }
  }

  my @inputs = $net->_input_ids();
  my @outputs = $net->_output_ids();
  my @feedbacks;
  for my $id (@all) {
    if( defined( $net->_feedback_taint( $id ) ) ) {
      push @feedbacks, $id;
    }
  }

  my @reverse_calc_sets;
  for my $set (@calc_sets) {
    unshift @reverse_calc_sets, $set;
  }


  my %vars = ( all => \@all,
	       all_count => (@all + 0),
	       calc_sets => \@calc_sets,
	       reverse_calc_sets => \@reverse_calc_sets,
	       inputs => \@inputs,
	       input_count => $net->opt( 'inputs' ),
	       outputs => \@outputs,
	       output_count => $net->opt( 'outputs' ),
	       weight_count => $weight_idx,
	       feedbacks => \@feedbacks,
	     );
  #print Data::Dumper::Dumper( \%vars );

  my $template = Template->new( { START_TAG => '(?:\}\ {0,2})?\[\%',
				  END_TAG => '\%\](?:\ {0,2}\{)?',
				  PRE_CHOMP => 2,
				  ABSOLUTE => 1,
				  RELATIVE => 1,
				} );

  my $code = "";
  #figure out where this module was loaded from - network.c.tmpl is in the same dir
  my $loc = $INC{"NetCompiler/C.pm"};
  $loc =~ s/\/[^\/]*$//g;
  #print "LOC: $loc\n";
  
  $template->process( "$loc/network.c.tmpl", \%vars, \$code ) or
    die $template->error();
  $code =~ s/; ;/;/gs;
  return $code;
}

sub _node_with_inputs {
  my $net = shift;
  my $id = shift;
  my $weight_idx = shift;
  my $weight_idx_table = shift;

  my @output_nodes = $net->_output_ids();
  my $is_output_node = 0;
  for my $outid (@output_nodes) {
    if( $id eq $outid ) {
      $is_output_node = 1;
      last;
    }
  }

  my %ins = $net->_list_raw_node_ins_weighted( $id );
  my @ins;
  my $fb = $net->_feedback_taint( $id );
  my $in_count = 0;
  my $fb_in_count = 0;
  my $norm_in_count = 0;
  while( my( $in, $weight ) = each(%ins) ) {
    next if $net->_disconnect_taint( $in );
    $in_count++;
    my $in_fb_grp = 0;
    if( defined $fb and defined $net->_feedback_taint( $in ) and
	$fb == $net->_feedback_taint( $in ) ) {
      $in_fb_grp = 1;
      $fb_in_count++;
    } else {
      $norm_in_count++;
    }
    push @ins, { id => $in,
		 random => (defined($weight)?0:1),
		 orig_weight => (defined($weight)?$weight:0),
		 weight_index => $$weight_idx,
		 in_fb_group => $in_fb_grp,
	       };
    $weight_idx_table->{$id}->{$in} = $$weight_idx;
    $$weight_idx += 1;
  }
  my @outs;
  my @out_ids = $net->_list_raw_node_outs( $id );
  my $out_count = 0;
  my $fb_out_count = 0;
  my $norm_out_count = 0;
  for my $out (@out_ids) {
    next if $net->_disconnect_taint( $out );
    $out_count++;
    my $in_fb_group = 0;
    if( defined $fb and defined $net->_feedback_taint( $out ) and 
	$fb == $net->_feedback_taint( $out ) ) {
      $in_fb_grp = 1;
      $fb_out_count++;
    } else {
      $norm_out_count++;
    }
    push @outs, { id => $out,
		  in_fb_group => $in_fb_group,
		};
  }
  return { id => $id,
	   is_output_node => $is_output_node,
	   in_count => $in_count,
	   fb_in_count => $fb_in_count,
	   norm_in_count => $norm_in_count,
	   in => \@ins,
	   out_count => $out_count,
	   fb_out_count => $fb_out_count,
	   norm_out_count => $norm_out_count,
	   out => \@outs,
	 };
}

1;
#end
