package Errorable;

use strict;

sub new {
    my $class = shift;
  my %args = @_;
  my $self = {};

  #make overriding 'new' possible
  if( ref( $class ) ) {
    bless $self, ref( $class );
  } else {
    bless $self, $class;
  }

  #subclass initialization goes here
  #subclass also has the opportunity to make the constructor fail
  return $self->_init(\%args);
}

sub _init {
  my $self = shift;
  my $args = shift;
  $self->{_ERROR} = undef;
  $self->debug_level( 0 );
  if( defined $args->{debug_level} ) {
    $self->debug_level( $args->{debug_level} );
  }
  return $self;
}

sub _clear_error {
  my $self = shift;

  #we want to keep the error if the caller was not the entrypoint
  my ( $package, $filename, $line, $subroutine, $hasargs,
       $wantarray, $evaltext, $is_require, $hints, $bitmask ) =
	 caller( 2 ); # 0 is us, 1 is caller, 2 is caller's caller
  unless( defined( $package ) and $self->isa( $package ) ) {
    #caller was entry point
    $self->{_ERROR} = undef;
  }
  return;
}

sub _set_error {
  my $self = shift;
  my $error = shift;

  if( defined $error ) {
    if( defined( $self->{_ERROR} ) ) {
      $self->{_ERROR} .= "\n$error";
    } else {
      $self->{_ERROR} = $error;
    }
  }
}

sub error {
  my $self = shift;
  return $self->{_ERROR};
}

sub debug_level {
  my $self = shift;
  if( @_ ) {
    $self->{_DEBUG_LEVEL} = shift;
  }
  return $self->{_DEBUG_LEVEL};
}

sub debug {
  my $self = shift;
  my $level = shift;

  if( $level <= $self->{_DEBUG_LEVEL} ) {
    print STDERR @_;
  }
}

sub debugf {
  my $self = shift;
  my $level = shift;

  if( $level <= $self->{_DEBUG_LEVEL} ) {
    printf STDERR @_;
  }
}

1;
#end
