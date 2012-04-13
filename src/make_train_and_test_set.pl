#!/usr/bin/perl -w

unless( @ARGV == 2 ) {
  print "usage: $0 <source> <training_set_output>\n";
  exit(-1);
}

my $infile = $ARGV[0];
my $outfile = $ARGV[1];

open SRC, "<$infile" or die "Can't open $infile: $!";

my $data;

{
  local $/ = undef;
  my $src = <SRC>;
  $data = eval $src;
  if( length( $@ ) ) {
    die "error in training source: $@";
  }
}

close SRC;

my( $inlen, $outlen, @train ) = setchecks( 'TRAIN', 'training', $data );
my( $inlen2, $outlen2, @test ) = setchecks( 'TEST', 'test', $data );
unless( $inlen == $inlen2 and $outlen == $outlen2 ) {
  die "training and test sets have different lengths: " .
    "$inlen/$outlen vs. $inlen2/$outlen2\n";
}

open OUT, ">$outfile" or die "Can't open $outfile for output: $!";
print OUT setstr( $inlen, $outlen, @train );
print OUT setstr( $inlen, $outlen, @test );

print "Wrote training/test sets to $outfile\n";

close OUT;
exit(0);

sub setstr {
  my( $inlen, $outlen, @set ) = @_;
  my $str = "";
  my $len = (@set + 0);
  $str .= "$len\n";
  for my $itm (@set) {
    $str .= "$inlen\n$outlen\n0\n";
    my @vals = ( @{$itm->[0]}, @{$itm->[1]} );
    for my $val (@vals) {
      if( $val == 0 ) {
	$val = -1;
      }
      $str .= "$val\n";
    }
  }
  return $str;
}

sub setchecks {
  my $key = shift;
  my $name = shift;
  my $dat = shift;
  unless( exists $dat->{$key} ) {
    die "Source has no $name set!";
  }
  unless( ref( $dat->{$key} ) eq 'ARRAY' ) {
    die "$name set must be an arrayref\n";
  }
  my @set = @{$dat->{$key}};
  unless( @set ) {
    die "$name set may not be empty\n";
  }
  for my $i (0..$#set) {
    unless( ref($set[$i]) eq 'ARRAY' ) {
      die "$name item #$i not an arrayref";
    }
    unless( @{$set[$i]} == 2 ) {
      die "$name item #$i must be a 2 item array";
    }
  }
  my $inlen = @{$set[0]->[0]};
  my $outlen = @{$set[0]->[1]};
  for my $i (0..$#set) {
    my $curinlen = @{$set[$i]->[0]};
    my $curoutlen = @{$set[$i]->[1]};
    unless( $inlen == $curinlen and $outlen == $curoutlen ) {
      die "$name item #$i has $curinlen in/$curoutlen out (not $inlen/$outlen)";
    }
  }
  return $inlen, $outlen, @set;
}
