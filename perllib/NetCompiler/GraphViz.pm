package NetCompiler::GraphViz;

sub __compile_net {
  my $net = shift;
  my %options = @_;
  my $skip_disconnected = 0;
  if( defined $options{no_disconnected} and $options{no_disconnected} ) {
    $skip_disconnected = 1;
  }
  my $graph = "digraph foo {\n";

  my $n = 0;

  my @feedback_colors = 
    (
     [ 'blue','LightBlue', 'DodgerBlue' ],
     [ 'green3','PaleGreen1','green2'],
     [ 'DarkOrchid1', 'lavender', 'MediumOrchid2' ],
     [ 'peru','wheat','burlywood'],
     [ 'yellow', 'LemonChiffon', 'yellow' ],
     [ 'DarkOrange1', 'orange', 'DarkOrange1' ] 
    );

  my @all_nodes = $net->_list_raw_nodes();
 NODE: for my $id (@all_nodes) {
    my $opt = '';
    my $color = 'grey50';
    my $label = '"\N (' . $net->_calc_order( $id ) . ')"';
    my @ftaint = sort( { $b cmp $a } $net->_list_feed_taints( $id ) );
    my $feedtaint = $ftaint[0];
    if( $net->_disconnect_taint( $id ) ) {
      if( $skip_disconnected ) {
	next NODE;
      }
      $color = 'red,fillcolor=pink,style=filled';
    } else {
      if( $net->_input_taint( $id ) == 1 ) {
	$opt .= ",shape=trapezium,orientation=180";
      }
      elsif( $net->_output_taint( $id ) == 1 ) {
	$opt .= ",shape=triangle,orientation=180";
      }
    }
    my $fbtaint = $net->_feedback_taint( $id );
    if( $fbtaint ) {
      my @colors = @{$feedback_colors[$fbtaint - 1]};
      $color = $colors[0] . ',fillcolor=' . $colors[1] . ',style=filled';
    }
    elsif( defined $feedtaint ) {
      my @colors = @{$feedback_colors[$feedtaint - 1]};
      $color = $colors[2];
    }
    $graph .= "  $id [label=$label,color=$color$opt];\n";
    my %ins = $net->_list_raw_node_ins_weighted( $id );
  IN: while( my( $in, $weight ) = each(%ins) ) {
      if( $skip_disconnected and $net->_disconnect_taint( $in ) ) {
	next IN;
      }
      my $edgecolor = "cyan4";
      my $addl = "";
      if( defined $weight ) {
	my $strength = abs( $weight / 256 );
	if( $strength > 255 ) {
	  $strength = 250;
	}
	if( $strength < 30 ) {
	  $strength = 25;
	}
	print "ST: $strength\n";
	#my $hex = sprintf( "%02X", 255 - $strength );
	my $pts = int($strength / 25);
	$addl .= ",style=\"setlinewidth($pts)\"";
	if( $weight > 0 ) {
	  $edgecolor = 'black';
	  #$edgecolor = "#" . $hex x 3;
	} else {
	  $edgecolor = 'red';
	  #$edgecolor = "#FF" . $hex x 2;
	}
      }
      $graph .= "   $in -> $id [color=\"$edgecolor\"$addl];\n";
    }
  }

  $graph .= "}\n";
  return $graph;
}

1;
#end
