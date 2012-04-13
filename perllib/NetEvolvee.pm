=head1 NAME

NetEvolvee - wraps NetCompiler neural networks for use by the Evolver module.

=head1 SYNOPSIS

Below is an example config file for Evolver, using NetEvolvee methods.

 use NetEvolvee;
 use Utility "progress_dots";

 return { load_individual => \&NetEvolvee::load,
          parents_per_individual => 2,
          average_over => 4,
          mutation_level => 5,
          select => sub { my $nselect = shift;
                          return NetEvolvee::choose_weighted
                            ( $nselect, 10, 5, @_ ); },
          kill => sub { return NetEvolvee::choose_weighted
                          ( 10, 10, 5, 'worst', @_ ); },
          get_starting_population => sub {
            my $project_dir = shift;
            return NetEvolvee::population_explosion( 100, #pop size
                                                     $project_dir,
                                                     'ancestor' );
          },
          introns => 0,
          recompile_genome => 0,
          remove_introns => 0,
          count_partials => 0.15,
          rm_killed => 1,
 };

=head1 DESCRIPTION

This module is not really intended to be used in a script, which explains the unusual format of the L</SYNOPSIS> section.

=head1 INTERFACE

=over

=cut

package NetEvolvee;

use NetCompiler;
use Mutation;
use Utility qw(progress_dots maketemp);

sub _compile_genome_opts {
  my $self = shift;
  my $project_def = ProjectConfig::get_config( $self->{PROJECT_DIR} );
  my %opts;
  if( defined $project_def->{introns} ) {
    if( ref( $project_def->{introns} ) eq 'HASH' ) {
      $opts{introns} = $project_def->{introns};
    } elsif( $project_def->{introns} ) {
      $opts{introns} = { min => 30, max => 300 };
    }
  }
  return %opts;
}

=item $net = load( <project_dir>, <network_id> )

Loads the specified network, which is stored in project_dir/network_id.gen (or .net).  Returns a NetEvolvee object.

=cut

sub load {
  my $proj_dir = shift;
  my $id = shift;
  my $stem = "$proj_dir/networks/$id";
  my $file_net = "$stem.net";
  my $file_gen = "$stem.gen";

  my $nc;
  my $self = bless { PROJECT_DIR => $proj_dir,
		     FILE => $file_gen,
		     STEM => $stem,
		     OBJECT => $obj }, NetEvolvee;
  if( -f $file_gen ) {
    $nc = new NetCompiler( filename => $file_gen, genome_mode => 1 );
    die "error loading network" unless defined $nc;
  } elsif( -f $file_net ) {
    $nc = new NetCompiler( filename => $file_net );
    die "error loading network" unless defined $nc;
    $nc->compile( 'genome', filename =>  $file_gen, $self->_compile_genome_opts() );
  } else {
    die "No file exists for net '$id' ($proj_dir)";
  }
  return $self;
}

=item $net = NetEvolvee->new(object => <obj>, temp => <temp_file>)

=item $net = $old_net->new( object => <obj>, temp => <temp_file> )

Creates a new NetEvolvee object.  If called as a method of an existing NetEvolvee object (as returned by load()), the location of the project directory will be copied from $old_net to $new_net.  <obj> should be a NetCompiler object, and <temp_file> should be the filename of the network definition (.gen or .net file).

=cut

sub new {
  my $pkg = shift;
  my %args = @_;
  my $obj = $args{object};
  my $tmpfile = $args{temp};

  my $self = { OBJECT => $obj, TEMP_FILE => $tmpfile };
  if( ref( $pkg ) ) {
    bless $self, ref( $pkg );
    $self->{PROJECT_DIR} = $pkg->{PROJECT_DIR}
  } else {
    bless $self, $pkg;
  }
  return $self;
}

=item $net->save( <project_dir>, <net_id> )

Saves the network to <project_dir>/<net_id>.gen.  Sets the project dir and id for the $net object, and removes the temporary file in which the network was previously stored.  If recompile_genome is set to a true value in the project config, the saved genome file is produced by a call to NetCompiler::compile.  Otherwise it is simply copied from the temp file.

=cut

sub save {
  my $self = shift;
  my $proj_dir = shift;
  my $id = shift;
  my $netdir = "$proj_dir/networks";
  my $project_def = ProjectConfig::get_config( $proj_dir );
  unless( -d $netdir ) {
    mkdir $netdir or die "Can't create $netdir: $!";
  }
  my $stem = "$netdir/$id";
  my $file = "$stem.gen";
  my $genfile = $self->{FILE};
  $genfile = $self->{TEMP_FILE} unless defined $genfile;
  if( defined $genfile and -f $genfile and
      not $project_def->{recompile_genome} ) {
    system( "cp $genfile $file" );
    if( defined $self->{TEMP_FILE} and $genfile eq $self->{TEMP_FILE} ) {
      unlink( $self->{TEMP_FILE} );
    }
  }
  elsif( defined $self->{OBJECT} ) {
    my $nc = $self->{OBJECT};
    $nc->compile( 'genome', filename => $file, $self->_compile_genome_opts() );
  }
  else {
    die "No .gen file and no in memory representation.";
  }
  $self->{STEM} = $stem;
  $self->{FILE} = $file;
  $self->{PROJECT_DIR} = $proj_dir;
}

=item $net->kill_files

Removes the files associate with this network.

=cut

sub kill_files {
  my $self = shift;
  system( "rm $self->{STEM}.*" );
}

=item $net->test_fitness

Calls the train_and_evaluate utility on the network, using the file 'training' in the network directory.  Calculates a fitness score between 0 and 2500 based on the results given by train_and_evaluate.

=cut

sub test_fitness {
  my $self = shift;

  my $so = $self->{STEM} . ".so";
  my $neurodir = $self->_get_neuro_dir();
  my $proj_dir = $self->{PROJECT_DIR};
  my $project_def = ProjectConfig::get_config( $proj_dir );

  my $ok = $self->_build_so();

  #if building the .so fails, fitness is zero
  unless( defined $ok ) {
    return 0;
  }

  open EVAL, "$neurodir/bin/train_and_evaluate $so $proj_dir/training 0.005 |";

  my %data;
  my $cur;
  #don't start parsing info until '=====...=====' appears on a line by itself
  while( my $line = <EVAL> ) {
    chomp $line;
    last if $line =~ m|^\={5}\.{3}\={5}$|;
  }
  while( my $line = <EVAL> ) {
    chomp $line;
    if( $line =~ /^(.*)\:\:$/ ) {
      $cur = {};
      $data{$1} = $cur;
    }
    elsif( $line =~ /^(.*?): (.*)$/ ) {
      my $k = $1;
      my $v = $2;
      $cur->{$k} = $v;
    }
  }
  close EVAL;
  unless( defined $data{training_statistics}->{learned_fraction} ) {
    print Data::Dumper::Dumper( \%data );
  }


  my $fitness = $data{training_statistics}->{learned_fraction} * 1200;
  if( $data{training_statistics}->{learned_fraction} > 0.9999 ) {
    #bonus for finishing early
    $fitness += (1 - $data{training_statistics}->{elapsed_seconds})*100;
    my $test_ok = $data{test_statistics}->{success_rate};
    my $partial_t = 0;
    if( defined $project_def->{count_partials} ) {
      my $partial_t = $project_def->{count_partials} *
	$data{test_statistics}->{partial_success_avg};
    }
    $fitness += ($test_ok + (1.0 - $test_ok)*$partial_t)*1200;
  }
  return $fitness;
}

=item $net->breed( <mutation_level>, [ <mate> ] );

If <mate> is supplied (it should be a NetEvolvee object), calls Mutation::cross_genomes() on the genome files of it and $net.  Either the result of the cross, or the genome of $net is then subject to Mutation::mutate_genome().  If remove_introns is set to a true value in the project config, the network is then processed by Mutation::purge_introns().

=cut

sub breed {
  my $self = shift;
  my $mutation_level = shift;
  my @spouses = @_;
  my $project_def = ProjectConfig::get_config( $self->{PROJECT_DIR} );

  die "Can't breed unless saved!" unless -f $self->{FILE};

  my $f_in;
  my @rm_files;
  if( @spouses > 1 ) {
    die "only 2 networks can mate at a time!";
  } elsif( @spouses == 1 ) {
    my $f1 = $self->{FILE};
    my $f2 = $spouses[0]->{FILE};

    my $f_cross = maketemp();
    chomp $f_cross;
    #should die on error
    Mutation::cross_genomes( $f1, $f2, $f_cross );
    $f_in = $f_cross;
    push @rm_files, $f_cross;
  }
  if( not @spouses ) {
    $f_in = $self->{FILE};
  }
  #always mutate:
  my $f_out = maketemp();
  chomp $f_out;
  Mutation::mutate_genome( $f_in, $f_out, $mutation_level );
  if( $project_def->{remove_introns} ) {
    my $f_muta = $f_out;
    $f_out = maketemp();
    chomp $f_out;
    push @rm_files, $f_muta;
    Mutation::purge_introns( $f_muta, $f_out );
  }
  my $new_nc = new NetCompiler( genome_mode => 1, filename => $f_out );
  die "Can't create child" unless( defined $new_nc );
  unlink( @rm_files );
  return ( $self->new( object => $new_nc, temp => $f_out ) );
}


sub _build_so {
  my $self = shift;

  my $nc = $self->{OBJECT};
  my $stem = $self->{STEM};
  my $c = "$stem.c";

  if( -f "$stem.so" ) {
    return 1;
  }

  #make the c code:
  $nc->compile( 'c', filename => $c );

  #compile it
  my $neurodir = $self->_get_neuro_dir();
  $ENV{NEURODIR} = $neurodir;
  system( "gmake -f $neurodir/perllib/NetEvolvee/evolve_makefile $stem.so > /dev/null 2>&1" );
  unlink( $c );
  if( -f "$stem.so" ) {
    return 1;
  } else {
    return undef;
  }
}

sub _get_neuro_dir {
  my $pkg;
  if( @_ ) {
    $pkg = ref($_[0]);
  } else {
    $pkg = 'NetEvolvee';
  }
  $pkg =~ s/\:\:/\//g;
  my $pfile = "$pkg.pm";
  my $path = $INC{$pfile};
  my $ptail = "/perllib/$pfile";
  $path =~ /(.*?)\Q$ptail\E/;
  my $pstem = $1;
  return $pstem;
}

=item select_n_best( <num>, @population )

Assumes @population is sorted by descending fitness, and simply returns a list of the first <num> elements.

=cut

sub select_n_best {
  my $nselect = shift;
  my @pop = @_;
  my @sel;
  while( $nselect ) {
    push @sel, pop( @pop );
    $nselect--;
  }
  return @sel;
}

=item choose_weighted( <num>, <multiple>, <max_scale>, [ 'worst' ], @population )

Chooses <num> items from @population by a weighted random selection.  Each item in @population should be a hashref, with a key called 'FITNESS'.  The item with the highest fitness will be <multiple> times more likely to be selected than the item with the lowest fitness, and the chance for items in between is scaled accordingly.  The difference between the lowest and highest will not be exaggerated by more than <max_scale>, however.  If the fourth parameter is the string 'worst', the probabilities will be reversed to favor the lowest fitness.

=cut

sub choose_weighted {
  my $nselect = shift;
  #how much better chance the best has than the worst:
  my $best_multiple = shift;
  #maximum amount to scale fitness by:
  my $max_scale = shift;
  my $inverted = 0;
  if( $_[0] eq 'worst' ) {
    $inverted = 1;
    shift;
  }
  my @pop = @_;

  #pass one: find max an min fitness:
  my $maxfit = $pop[0]->{FITNESS};
  my $minfit = $pop[0]->{FITNESS};
  for my $ind (@pop) {
    my $fit = $ind->{FITNESS};
    if( $fit < $minfit ) {
      $minfit = $fit;
    }
    elsif( $fit > $maxfit ) {
      $maxfit = $fit;
    }
  }
  #the -1 is b/c we want the worst to scale to 1
  my $scale = 1;
  if( $maxfit - $minfit ) {
    $scale = ($best_multiple - 1)/($maxfit - $minfit);
  }
  if( $max_scale > 0 and $scale > $max_scale ) {
    $scale = $max_scale;
  }
  my $base = $minfit;
  #if we invert min & max, we have to use -scale (otherwise, above is same)
  #so fix it here:
  if( $inverted ) {
    $base = $maxfit;
    $scale *= -1;
  }
  my $total_score = 0;
  my @list = ( map { my $score = ($_->{FITNESS} - $base)*$scale +1;
		     $total_score += $score;
		     { IND => $_, SCORE => $score }
		   } @pop );
  #now we just pick a number between 0 and $total_score,
  #go through the list, and subtract each score from the number,
  #until the number is < the current score, at which point we have our boy..
  #it doesn't even matter which direction you go in, like picking a
  #random spot on the edge of a wheel w/ different size 'pie' pieces
  my @ret;
  while( @ret < $nselect ) {
    my $spot = rand( $total_score );
    my $n = 0;
    while( $spot > $list[$n]->{SCORE} ) {
      $spot -= $list[$n]->{SCORE};
      $n++;
    }
    push @ret, $list[$n]->{IND};
    #adjust total score b/c this individual no longer is part of the pool:
    $total_score -= $list[$n]->{SCORE};
    splice @list, $n, 1;
  }
  return @ret;
}

=item kill_worst( [ percent => <pct>, ] @population )

Returns a the last <pct> percent of @population, which should be sorted in order of descending fitness.  If <pct> is not supplied, 10 is used.

=cut

sub kill_worst {
  my $percent = 10;
  if( $_[0] eq 'percent' ) {
    shift @_;
    $percent = shift;
  }
  my @pop = @_;
  my $kill_fraction = $percent/100;
  #kill the worst n%:
  my $n = int((@pop + 0)*$kill_fraction);
  my @kill;
  
  while( $n ) {
    push @kill, shift( @pop );
    $n--;
  }
  return @kill;
}

=item population_explosion( <num>, <project_dir>, <parent_id> )

Returns a list of <num> NetEvolvee objects, each of which is created by mutating the network found in project_dir/networks/parent_id.net (or .gen), with a mutation level of 10.

=cut

sub population_explosion {
  my $npop = shift;
  my $dir = shift;
  my $parent = shift;
  my $granddaddy = load( $dir, $parent );
  my @pop;

  print "Making start population";
  for my $i (1..$npop) {
    push @pop, $granddaddy->breed( 10 );
    progress_dots( 50, $i, $npop );
  }
  print "done\n";
  return @pop;
}


1;
#end.

=back

=cut
