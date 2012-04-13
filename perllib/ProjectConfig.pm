=head1 NAME

ProjectConfig - provides a cached loading mechanism for Evolver and NetEvolvee.

=head1 SYNOPSIS

 use ProjectConfig;

 $config = ProjectConfig::get_config( 'project_dir' );

=head1 DESCRIPTION

This package only provides one function: get_config, which loads the file 'project_dir/config', evaluates it, and returns the return value from eval().  The return values are cached, so that on subsequent calls with the same value of 'project_dir', the config file will not be re-read unless it has changed on disk.  Also makes sure that the value returned by config is a hash reference which contains the keys 'load_individual', 'parents_per_individual', 'select', 'kill', 'get_starting_population', and 'mutation_level'.  If not, it will raise a fatal error with die().

=cut

package ProjectConfig;

use Carp qw(confess);

my %projects;

sub get_config {
  my $project_dir = shift;

  if( $project_dir !~ /\/$/ ) {
    $project_dir .= '/';
  }

  unless( -d $project_dir ) {
    die "project dir '$project_dir' does not exist";
  }

  my $def_file = $project_dir . "config";

  if( defined $projects{$project_dir} ) {
    my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
	$atime,$mtime,$ctime,$blksize,$blocks) = stat($def_file);
    if( $mtime <= $projects{$project_dir}->{time} ) {
      return $projects{$project_dir}->{def};
    }
  }

  my $defcont;
  {
    local $/ = undef;
    open DEF, "<$def_file" or confess "Can't open project def ($def_file): $!";
    $defcont = <DEF>;
    close DEF;
  }
  my $def = eval( $defcont );
  die "project def error: $@" if length($@);
  #check to make sure crucial fields are present:
  my @fields = (qw(load_individual parents_per_individual select kill),
		qw(get_starting_population mutation_level));
  for my $fld (@fields) {
    unless( defined $def->{$fld} ) {
      die "Project def must include field '$fld'.";
    }
  }
  $def->{dir} = $project_dir;
  $projects{$project_dir} = { def => $def, time => time() };
  return $def;
}

1;
#end
