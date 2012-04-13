#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/time.h>
#include <time.h>

#include "neural.h"

void printdbls( double *dbls, int count ) {
  int i;
  for( i=0; i<count; i++ ) {
    printf( "%e ", dbls[i] );
  }
}

int main( int argc, char *argv[] ) {
  net_definition net;
  net_io **training_set, **test_set;
  net_io *training_buf, *test_buf;
  net_weights wght;
  int training_set_size, test_set_size;
  float time_limit;
  FILE *trainf;
  //usage: t_a_e network_lib.so training_file weights_output [weights_input]
  // (weights_input is for later)
  char *net_fname, *training_fname, *wghts;
  training_statistics train_stats;
  test_statistics test_stats;

  if( argc < 4 ) {
    fprintf( stderr, "Usage: %s <network> <training_file> <timelimit> [<output_weights>]\n",
	     argv[0] );
    exit( -1 );
  }

  net_fname = argv[1];
  training_fname = argv[2];
  sscanf( argv[3], "%f", &time_limit );

  //load the neural net:
  if( 0 > load_net( net_fname, &net ) ){
    fprintf( stderr, "%s: can't initialize neural network: %s\n", 
	     argv[0], neural_error() );
    exit( -1 );
  }

  trainf = fopen( training_fname, "r" );
  if( trainf == NULL ) {
    fprintf( stderr, "%s: can't open training file %s: %s\n",
	    argv[0], training_fname, strerror( errno ) );
    exit( -1 );
  }

  if( 0 > fread_net_io_set( trainf, &training_buf, &training_set, 
			    &training_set_size, &net, 0 ) ) {
    fprintf( stderr, "%s: can't load training set: %s\n",
	     argv[0], neural_error() );
    exit( -1 );
  }
  
  if( 0 > fread_net_io_set( trainf, &test_buf, &test_set,
			    &test_set_size, &net, 0 ) ) {
    fprintf( stderr, "%s: can't load test set: %s\n",
	     argv[0], neural_error() );
    exit( -1 );
  }

  //almost ready for training

  starting_weights( &net, &wght );

  train_on_set( &net, training_set, training_set_size,
		&wght, 0.1, (double)time_limit, &train_stats, 0 );

  test_on_set( &net, test_set, test_set_size, &wght, &test_stats, 0 );

  printf( "=====...=====\n" );

  printf( "training_statistics::\n" );

  printf( "iteration_count: %d\n", train_stats.iteration_count );
  printf( "presentation_count: %d\n", train_stats.presentation_count );
  printf( "training_count: %d\n", train_stats.training_count );
  printf( "correct_count: %d\n", train_stats.correct_count );
  printf( "learned_count: %d\n", train_stats.learned_count );
  printf( "elapsed_seconds: %f\n", train_stats.elapsed_seconds );
  printf( "correct_rate: %f\n", train_stats.correct_rate );
  printf( "learned_fraction: %f\n", train_stats.learned_fraction );
  printf( "...\n" );
  
  printf( "test_statistics::\n" );

  printf( "successful_items: %d\n", test_stats.successful_items );
  printf( "success_rate: %f\n", test_stats.success_rate );
  printf( "partial_success_avg: %f\n", test_stats.partial_success_avg );
  printf( "...\n" );
  
}
  
