=head1 NAME

Utility - provides two utility functions

=head1 SYNOPSIS

  use Utility qw(progress_dots maketemp);

  print "Doing something"
  for my $i (1..$n) {
    do_something();
    progress_dots( 50, $i, $n );
  }
  print "done\n"

  $temp_file = maketemp();

=head1 DESCRIPTION

This package provides two utility functions which are used by Evolver.pm and NetEvolvee.pm

=head1 INTERFACE

=over

=cut

package Utility;

use POSIX qw(uname);

BEGIN {
  @Utility::ISA = qw(Exporter);
  @EXPORT_OK = qw(progress_dots maketemp);
  my( $uname ) = uname();
  print "UNAME: **$uname**\n";
  if( $uname eq 'FreeBSD' ) {
    $Utility::mktemp_cmd = 'mktemp -t tmp';
  } else {
    $Utility::mktemp_cmd = 'mktemp';
  }
  print "MKTCMD: $mktemp_cmd\n";
}

my %progs;

=item progress_dots( <num_dots>, <num_completed>, <num_total> );

Prints period characters "." to STDOUT as a text-only progress bar.  Should be called with steadily increasing values of <num_completed>; if this value decreases from one call to the next the progress "bar" is restarted.  Remembers the previous value of <num_completed> and prints an appropriate number of dots.  If the value of <num_completed> actually reaches <num_total>, exactly <num_dots> will have been printed.

=cut

sub progress_dots {
  my $n_dots = shift;
  my $done = shift;
  my $total = shift;

  my( $package, $filename, $line, $sub ) = caller(1);

  my $key = "$package$filename$line$sub";
  $progs{$key} = 0 unless defined $progs{$key};
  my $dots_compl = int(($done/$total)*$n_dots);
  #this condition indicates that the prog bar is restarted.
  if( $progs{$key} > $dots_compl ) {
    $progs{$key} = 0;
  }
  if( $progs{$key} < $dots_compl ) {
    print "." x ($dots_compl - $progs{$key});
    $progs{$key} = $dots_compl;
  }
}

=item $tempfile = maketemp()

Tries to provide a uniform interface to the mktemp command across several operating systems, so that mktemp will respond to the 'TMPDIR' environment variable.  It is known to work on Debian 'sid', and versions of Redhat, and FreeBSD.  It should be tested before use to ensure proper operation.  Returns the path to the temporary file created.

=cut

sub maketemp {
  open MKT, "$mktemp_cmd |";
  my $f = <MKT>;
  chomp $f;
  unless(-f $f ) {
    die "mktemp failed ($mktemp_cmd --> $f )";
  }
  return $f;
}

1;
#end

=back

=cut
