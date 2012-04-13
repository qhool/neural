=head1 NAME

Evolver - implements a generic genetic algorithm.

=head1 SYNOPSIS

 use Evolver;
 $evo = new Evolver( project => 'project_dir',
                     data_log => 'log_name' );
 for my $i (0..$number_of_generations) {
   $evo->run_generation();
 }

=head1 DESCRIPTION

Evolver implements a genetic algorithm in a generic form.  All particulars of genome encoding, reproduction, selection, fitness functions, etc. are provided in the configuration file.  Individuals which are evolved are expected to implement an object oriented interface (see L</OBJECT INTERFACE>).

=head1 INTERFACE

=over

=cut

package Evolver;

use Storable qw(nstore_fd);
use Time::HiRes qw(gettimeofday);
use Digest::MD5 qw(md5_base64);
use POSIX qw(strftime uname);

use Errorable;
use Utility qw(progress_dots);
use ProjectConfig;

BEGIN {
  @Evolver::ISA = qw(Errorable);
}

#population individual interface:
# $i = load_individual(<proj_dir>,<id>) #provided in project def?
# $i->save(<proj_dir>,<id>)
# $i->test_fitness()
# $i->breed( @other_parents );

=item Evolver->new( project => <project_dir, [ data_log => <logfile> ] )

Creates a new Evolver object, with the configuration defined in <project_dir>/config.  If data_log is specified, lots of generation-by-generation data will be written to <logfile>_<date-time string>.dat, using Storable.  See L</CONFIGURATION> for the options in the config file.

=cut

sub _init {
  my $self = shift;
  my %args = %{$_[0]};
  $self = $self->SUPER::_init(@_);
  if( defined $self ) {
    #all aspects of the project are in a file
    if( defined $args{project} ) {
      my $def = ProjectConfig::get_config( $args{project} );
      #populate the hash with optional fields:
      my @optional = qw(average_over rm_killed);
      for my $fld (@optional) {
	unless( exists $def->{$fld} ) {
	  $def->{$fld} = undef;
	}
      }
      $self->{PROJECT_DEF} = $def;
      $self->{POPULATION} = {};
      if( -f $self->dir() . "/state" ) {
	unless( $self->load_state( $self->dir() . "/state" ) ) {
	  die "Can't load project state: " . $self->error();
	}
      } else {
	#create the starting generation
	$self->_set_generation( 0 );
	my @pop = $self->get_starting_population( $self->dir() );
	print "Saving start population";
	my $ndone = 0;
	for my $indiv (@pop) {
	  my $id = make_identifier();
	  $indiv->save( $self->dir(), $id );
	  $self->add_individual( $id, $indiv );
	  $ndone++;
	  progress_dots( 50, $ndone, (@pop + 0) );
	}
	print "done\n";
      }
    }
  }
  if( defined $args{data_log} ) {
    my $logfile = strftime( "$args{data_log}_%Y%m%d_%H%M%S.dat", localtime() );
    my $fh = new IO::Handle;
    open $fh, ">$logfile" or die "Can't open data log ($logfile): $!";
    $self->{DATA_LOG} = $fh;
    #Storable doesn't do CODE refs, so clean them out before storing"
    my %proj_data = %{$self->{PROJECT_DEF}};
    for my $k (keys( %proj_data ) )  {
      if( ref( $proj_data{$k} ) eq 'CODE' ) {
	delete $proj_data{$k};
      }
    }
    nstore_fd( { project_def => \%proj_data }, $fh );
    $Storable::forgive_me = $oldforgive;
  }
  return $self;
}

sub add_individual {
  my $self = shift;
  my( $id, $individual ) = @_;
  $self->_clear_error();
  if( defined $self->{POPULATION}->{$id} ) {
    $self->_set_error( "Duplicate individual ID: $id" );
    return undef;
  }
  $self->{POPULATION}->{$id} = { ID => $id,
				 OBJECT => $individual,
				 AGE => 0,
			       };
  return $self->{POPULATION}->{$id};
}

sub get_individual {
  my $self = shift;
  my $id = shift;

  return $self->{POPULATION}->{$id};
}

sub all_individuals {
  my $self = shift;
  return values( %{$self->{POPULATION}} );
}

sub remove_individual {
  my $self = shift;
  my $id = shift;
  if( $self->rm_killed() ) {
    $self->{POPULATION}->{$id}->{OBJECT}->kill_files();
  }
  delete $self->{POPULATION}->{$id};
}

sub generation_count {
  my $self = shift;
  return $self->{GENERATION};
}

sub _set_generation {
  my $self = shift;
  $self->{GENERATION} = shift;
}

sub _incr_generation {
  my $self = shift;
  $self->{GENERATION}++;
}

=item $evo->run_generation

Calls fitness function for all networks, does callbacks to select networks to kill, and networks for reproduction, calls reproduction function to produce new networks, and writes data to log file if data_log option was given to new().

=cut

sub run_generation {
  my $self = shift;
  $self->_clear_error();
  my $tot_fitness = 0;
  my $nfit = 0;
  my $retained_tot_fit = 0;
  my $nretained = 0;
  my $tot_age = 0;
  my $ret_max_fit = 0;
  my $ret_min_fit = 100000000;
  my $max_fit = 0;
  my $min_fit = 100000000;
  my $new_tot_fit = 0;
  my $n_new = 0;
  my $new_max_fit = 0;
  my $new_min_fit = 100000000;
  my @popdata;

  my @pop = $self->all_individuals();
  print "Calculating fitness";
  for my $individual (@pop) {
    my $n = 1;
    my $avg_over = $self->average_over();
    $avg_over = 1 unless defined $avg_over;
    unless( defined $individual->{FITNESS} ) {
      $n = $avg_over;
    }
    my $tot = 0;
    #print "->>$avg_over / $n\n";
    for my $i (1..$n) {
      $tot += $individual->{OBJECT}->test_fitness();
    }
    my $curr = $tot/$n;
    #print "cur: $tot / $n = $curr\n";
    if( defined $individual->{FITNESS} ) {
      #print "prefit: $individual->{FITNESS}\n";
      my $nsamp = $avg_over + $individual->{AGE};
      $individual->{FITNESS} = ( ($curr/$nsamp + $individual->{FITNESS}) *
				 ($nsamp/($nsamp + 1)) );
      #print "fit: $curr, $avg_over --> $individual->{FITNESS}\n";
    } else {
      $individual->{FITNESS} = $curr;
    }
    $tot_fitness += $individual->{FITNESS};
    $nfit++;
    $tot_age += $individual->{AGE};
    push @popdata, [$individual->{AGE},$individual->{FITNESS}];
    if( $individual->{AGE} > 0 ) {
      $retained_tot_fit += $individual->{FITNESS};
      $nretained++;
      if( $ret_max_fit < $individual->{FITNESS} ) {
	$ret_max_fit = $individual->{FITNESS};
      }
      if( $ret_min_fit > $individual->{FITNESS} ) {
	$ret_min_fit = $individual->{FITNESS};
      }
    } else {
      $new_tot_fit += $individual->{FITNESS};
      $n_new++;
      if( $new_max_fit < $individual->{FITNESS} ) {
	$new_max_fit = $individual->{FITNESS};
      }
      if( $new_min_fit > $individual->{FITNESS} ) {
	$new_min_fit = $individual->{FITNESS};
      }
    }
    if( $max_fit < $individual->{FITNESS} ) {
      $max_fit = $individual->{FITNESS};
    }
    if( $min_fit > $individual->{FITNESS} ) {
      $min_fit = $individual->{FITNESS};
    }
    progress_dots( 50, $nfit, (@pop + 1) );
    $individual->{AGE}++;
  }
  print "done\n";
  @pop = sort( { $a->{FITNESS} <=> $b->{FITNESS} } @pop );
  my $avg_fitness = $tot_fitness/$nfit;
  my $avg_ret_fitness = 0;
  if( $nretained ) {
    $avg_ret_fitness = $retained_tot_fit/$nretained;
  }
  my $avg_new_fitness = 0;
  if( $n_new ) {
    $avg_new_fitness = $new_tot_fit/$n_new;
  }
  my $avg_age = $tot_age/$nfit;

  #get the ones to kill:
  my @hit_list = $self->kill( @pop );
  my $nkill = @hit_list + 0;
  my $ppi = $self->parents_per_individual();
  my $nparents = ($ppi > $nkill)?$ppi:$nkill;
  my @parent_pool = $self->select( $nparents, @pop );
  my $nkids = $nkill;
  print "Generating new individuals";
  while( $nkids ) {
    #take the next 'primary parent'
    my $primary = shift @parent_pool;
    #make a copy so we don't mess up the order of the main pool
    my @secondary_pool = @parent_pool;
    #put the primary back at the end of the line
    push @parent_pool, $primary;
    my @secondaries;
    while( @secondaries + 1 < $ppi ) {
      my $idx = int( rand( @secondary_pool + 0 ) );
      push @secondaries, splice( @secondary_pool, $idx, 1 );
    }
    my $kid = $primary->{OBJECT}->breed( $self->mutation_level(), 
					 (map {$_->{OBJECT}} @secondaries) );
    my $id = make_identifier();
    $kid->save( $self->dir(), $id );
    $self->add_individual( $id, $kid );
    $nkids--;
    progress_dots( 50, $nkill - $nkids, $nkill );
  }
  print "done\n";
  #kill off the deselected:
  for my $hit (@hit_list) {
    $self->remove_individual( $hit->{ID} );
  }
  print "Generation ", $self->generation_count(), ": ", (@pop + 0), " individuals, $nkill turnover\n";
  printf( 'Avg fitness: %0.3f (avg non-new: %0.3f / max: %0.3f) Avg age: %0.2f' .
	  "\n", $avg_fitness, $avg_ret_fitness, $ret_max_fit, $avg_age );
  $self->_incr_generation();
  $self->save_state( $self->dir() . "/tmp_state" );
  if( defined $self->{DATA_LOG} ) {
    my %data = ( generation => $self->generation_count(),
		 population => (@pop + 0),
		 popdata => \@popdata,
		 turnover => $nkill,
		 avg_fitness => $avg_fitness,
		 ret_avg_fitness => $avg_ret_fitness,
		 ret_max_fit => $ret_max_fit,
		 ret_min_fit => $ret_min_fit,
		 new_avg_fitness => $avg_new_fitness,
		 new_max_fit => $new_max_fit,
		 new_min_fit => $new_min_fit,
		 max_fit => $max_fit,
		 min_fit => $min_fit,
		 avg_age => $avg_age );
    nstore_fd( \%data, $self->{DATA_LOG} );
  }
}

sub save_state {
  my $self = shift;
  my $file = shift;
  my @pop = $self->all_individuals();
  my @savepop;
  for my $ind (@pop) {
    my %nu = %$ind;
    delete $nu{OBJECT};
    push @savepop, \%nu;
  }
  my $state = { GENERATION => $self->generation_count(),
		POPULATION => \@savepop };
  Storable::nstore( $state, $file );
}

sub load_state {
  my $self = shift;
  my $file = shift;
  $self->_clear_error();
  my $state = Storable::retrieve( $file );
  unless( defined $state ) {
    $self->_set_error( "error reading '$file': $!" );
    return undef;
  }
  my @pop = @{$state->{POPULATION}};
  $self->{GENERATION} = $state->{GENERATION};
  for my $ind (@pop) {
    my $obj = $self->load_individual( $self->dir(), $ind->{ID} );
    my $individual = $self->add_individual( $ind->{ID}, $obj );
    while( my($k,$v) = each(%$ind) ) {
      $individual->{$k} = $v;
    }
  }
  return 1;
}

BEGIN {
  $Evolver::hoststr = join( "", uname() );
}

sub make_identifier {
  my $pid = $$;
  my( $secs, $usecs ) = gettimeofday();
  my $rnd = rand( 2 << 30 );
  my $key = md5_base64("$hoststr$pid$secs$usecs$rnd");
  #want the guid to be usable in filenames, so get rid of / and + chars:
  $key =~ tr/\/\+/_\./;
  return $key;
}


#provide access methods to project def fields:
sub AUTOLOAD {
  my $self = $_[0];
  #get the actual function name:
  $AUTOLOAD =~ /::([^:]*)$/;
  my $fldname = $1;

  #print STDERR "Auto: $fldname\n";

  if( exists $self->{PROJECT_DEF}->{$fldname} ) {
    my $subname = 'Evolver::' . $fldname;
    my $subcode = "sub $subname" . "{ \n" .
      ' my $self = shift;' . "\n" . 'return ';
    my $fncode = '$self->{PROJECT_DEF}->{' . $fldname . '}';
    if( ref( $self->{PROJECT_DEF}->{$fldname} ) eq 'CODE' ) {
      $subcode .= "&{$fncode}" . '(@_)';
    } else {
      $subcode .= "$fncode";
    }
    $subcode .= ";\n}\n" . 'return \&' . $subname . ";\n";
    #print STDERR "SUBCODE: $subcode\n";
    my $newsub = eval $subcode;
    #print STDERR "rf: ", ref( $newsub ), "\n";

    die "can't generate $fldname(): $@" if length($@);
    goto & $newsub;
  }
  else {
    die "unknown field: $fldname";
  }
}

#this is here to prevent AUTOLOAD from trying to provide a DESTROY sub
sub DESTROY {
}

1;

#end

=back

=head1 OBJECT INTERFACE

The individuals being evolved need to implement the interface defined here.  $individual is used for the 'individual' object in this specification.

=over

=item $individual->save( <project_dir>, <id> )

This individual should be stored under <project_dir> and be retrievable by <id> using the load() sub defined in the config file.

=item $individual->test_fitness

Should return a numerical fitness value for the individual.

=item $individual->breed( <mutation_level>, [mate, ...] )

$individual should combine with the zero or more mates supplied to produce a single offspring, whose object should be returned.

=item $individual->kill_files

All files used to store this individual should be purged from the project dir.

=back

=head1 CONFIGURATION

The configuration of the genetic algorithm is defined in 'project_dir/config'.  This file should be a Perl program which will return a configuration hash when eval()ed.  The items in this hash are listed below:

=head2 Mandatory Directives

=over

=item load_individual

Should contain a subroutine reference: load( 'project_dir', ID ), which will return an object representing the individual represented by ID.

=item parents_per_individual

The number (plus one) of individuals to pass to the breed() function of the 'individual' object.  The value 1 corresponds to asexual reproduction, 2 to sexual reproduction, and 3+ to something more exotic.

=item mutation_level

This parameter is simply passed to the breed() function.

=item select

Should contain a sub reference: select( <number>, @population ).  @population will be a list of hashes each having a 'FITNESS' value.  The sub should select <number> items from @population and return them.

=item kill

Should contain a sub reference: kill( @population ).  @population is the same as for 'select' above.  The sub should choose some number of items from the population list, and return them.  The number of items in this list will be the same as the <number> parameter passed to the 'select' callback.

=item get_starting_population

Contains a sub reference which takes as its argument the project dir.  Should return a starting population.  The size of the starting population is the constant population size for the rest of the experiment.

=back

=head2 Optional Directives

=over

=item average_over

If this option is supplied, it specifies the number of times test_fitness() will be called and the values averaged together to calculate the fitness for new individuals.

=item rm_killed

If this option is present, and true, kill_files() will be called on all individuals removed from the population.

=back

=head2 Other Directives

The 'individual' object methods or other configured subs are also free to include their own configuration directives in the config file.  They can access the configuration using the ProjectConfig module, as Evolver.pm does.

=cut
