#ifndef __NEURAL_H
#define __NEURAL_H

#include <stdio.h>
#include <time.h>

struct net_info {
  int input_count;
  int weight_count;
  int output_count;
  int node_count;
};

typedef int (*calc_network_fn)( int *inputs, int input_count,
				int *outputs, int output_count,
				double *weights, int weight_count,
				double *node_values, int node_count,
				int feedback_limit, double feedback_convergence );
typedef int (*setup_initial_weights_fn)( double *weights, int weight_count,
					 unsigned int *seed, int make_seed );
typedef void (*train_net_fn)( double *weights, 
			      double *weight_changes, int weight_count,
			      double *node_values, int node_count,
			      int *correct_outputs, int output_count,
			      int feedback_limit, double feedback_convergence,
			      double training_level );
typedef void (*net_info_fn)( struct net_info *info );

typedef struct _net_def_STRUCT {
  calc_network_fn calculate;
  setup_initial_weights_fn setup_weights;
  train_net_fn train;
  net_info_fn get_info;
  struct net_info info;
  void *dlref;
  int feedback_limit;
  double feedback_convergence;
} net_definition;

typedef struct _net_io_STRUCT {
  int *inputs;
  int input_count;
  int *outputs;
  int output_count;
  double *node_values;
  int node_count;
} net_io;

typedef struct _net_weights_STRUCT {
  double *weights;
  int weight_count;
} net_weights;

char *neural_error();

int load_net( const char *net_file, net_definition *def );

//allocate (zeroed) memory for arrays in net_io structure
int init_net_io( net_definition *def, net_io *io, int with_internal_state );
//allocates (zeroed) memory for weights array in structure
int init_net_weights( net_definition *def, net_weights *weights );
int starting_weights( net_definition *def, net_weights *weights );

void free_net_io( net_io *io );
void free_net_weights( net_weights *weights );

#define COPY_INPUT 1
#define COPY_OUTPUT 2
#define COPY_INTERNAL 4
#define COPY_ALL 7

int copy_net_io( net_io *dest, net_io *src, int copy );

//returns 1 if a.output == b.output, -1 * [# correct] otherwise
int test_io_output( net_io *a, net_io *b );

void apply_weights( net_weights *weights, net_weights *changes );

int calc_net( net_definition *def, net_io *io, net_weights *weights );

#define NET_CORRECT_OUTPUTS_GIVEN 2
#define NET_APPLY_WEIGHT_CHANGES 4
#define NET_ACCUMULATE_WEIGHT_CHANGES 8

void train_net( net_definition *def, net_io *io,
		net_weights *weights,
		net_weights *weight_changes,
		double training_level,
		unsigned int flags );

typedef struct _training_statistics_STRUCT {
  int iteration_count;
  int presentation_count;
  int training_count;
  int correct_count;
  int learned_count;
  float elapsed_seconds;
  float correct_rate;
  float learned_fraction;
} training_statistics;

#define TRAIN_ON_SUCCESS 1
  
void train_on_set( net_definition *def, 
		   net_io **training_set, int set_count,
		   net_weights *weights,
		   double training_level,
		   double timeout_secs,
		   training_statistics *stats,
		   int flags );

typedef struct _test_statistics_STRUCT {
  int successful_items;
  float success_rate;
  //percent of correct outputs over unsuccessful examples
  float partial_success_avg;
} test_statistics;

void test_on_set( net_definition *def,
		  net_io **test_set, int set_count,
		  net_weights *weights,
		  test_statistics *stats,
		  int flags );
		  

//write weights to filehandle as ascii representation
int fwrite_weights( FILE *file, net_weights *weights );
int fread_weights( FILE *file, net_weights *weights );

int fwrite_net_io( FILE *file, net_io *io );;
int fread_net_io( FILE *file, net_io *io );
int fread_net_io_set( FILE *file, net_io **set_buf, net_io ***set, int *count,
		      net_definition *def, int with_internal_state );

#endif /* __NEURAL_H */		   
