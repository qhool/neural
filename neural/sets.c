#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/time.h>

#include "neural.h"

void train_on_set( net_definition *def, 
		   net_io **training_set, int set_count,
		   net_weights *weights,
		   double training_level,
		   double timeout_secs,
		   training_statistics *stats,
		   int flags ) {
  struct timeval start_tv, stop_tv, cur_tv;
  net_io state;
  net_weights weight_changes;
  //these vars are used to visit the examples in random order each time.
  unsigned char *visited;
  int num_visited, cur_failure_count = 1;
  int index;
  int jump;
  
  int do_training = 0;

  //zero training stats:
  memset( (void *)stats, 0, sizeof( training_statistics ) );

  init_net_weights( def, &weight_changes );
  starting_weights( def, weights );
  init_net_io( def, &state, 1 );
  
  //start_tv is used to calculate more precicely how long it took:
  gettimeofday( &start_tv, (struct timezone *)NULL );

  visited = malloc( sizeof(char) * set_count );
  
  srand( time(NULL) );

  while( gettimeofday( &cur_tv, NULL ) == 0 &&
	 timeout_secs > 
	 (double)( cur_tv.tv_sec - start_tv.tv_sec ) +
	 ( (double)( cur_tv.tv_usec - start_tv.tv_usec ) / 1000000 ) &&
	 cur_failure_count > 0 ) {
    stats->iteration_count++;
    //this array keeps track of which items have been visited this iteration
    memset( (void *)visited, 0, sizeof(char) * set_count );
    cur_failure_count = 0;
    for( num_visited = 0; num_visited < set_count; num_visited++ ) {
      jump = rand() % (set_count - num_visited);
      //count out the [jump]th unvisited item:
      index = 0;
      while( jump > 0 || visited[index] ) {
	if( !visited[index] ) {
	  jump--;
	}
	index++;
      }
      visited[index] = 1;
      copy_net_io( &state, training_set[index], COPY_INPUT );
      calc_net( def, &state, weights );
      stats->presentation_count++;
      do_training = 0;
      if( 0 < test_io_output( &state, training_set[index] ) ) {
	stats->correct_count++;
	if( flags & TRAIN_ON_SUCCESS ) {
	  do_training = 1;
	}
      } else {
	do_training = 1;
	cur_failure_count++;
      }
      if( do_training ) {
	copy_net_io( &state, training_set[index], COPY_OUTPUT );
	train_net( def, &state, weights, &weight_changes, training_level, 
		   NET_CORRECT_OUTPUTS_GIVEN | NET_APPLY_WEIGHT_CHANGES );
	stats->training_count++;
      }
    }
  }
  gettimeofday( &stop_tv, (struct timezone *)NULL );
  
  stats->elapsed_seconds = (float)(stop_tv.tv_sec - start_tv.tv_sec) + 
    ((float)(stop_tv.tv_usec - start_tv.tv_usec))/1000000.0;
  stats->correct_rate = (float)(stats->correct_count) / 
    (float)(stats->presentation_count);
  stats->learned_count = set_count - cur_failure_count;
  stats->learned_fraction = (float)(stats->learned_count) /
    (float)(set_count);
}

void test_on_set( net_definition *def,
		  net_io **test_set, int set_count,
		  net_weights *weights,
		  test_statistics *stats,
		  int flags ) {
  net_io state;
  int partial_success_count = 0;
  int partial_output_count = 0;
  int i, test_result;
  
  init_net_io( def, &state, 1 );
  memset( (void *)stats, 0, sizeof( test_statistics ) );
  
  for( i=0; i<set_count; i++ ) {
    copy_net_io( &state, test_set[i], COPY_INPUT );
    calc_net( def, &state, weights );
    test_result = test_io_output( &state, test_set[i] );
    if( test_result > 0 ) {
      stats->successful_items++;
    } else {
      partial_success_count += (-1)*test_result;
      partial_output_count += state.output_count;
    }
  }
  stats->success_rate = (float)stats->successful_items / (float)set_count;
  if( stats->successful_items == set_count ) {
    stats->partial_success_avg = 0.0;
  } else {
    stats->partial_success_avg = ((float)partial_success_count / 
				  (float)partial_output_count);
  }
}
      
      
    
  
