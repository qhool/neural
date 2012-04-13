#include <stdlib.h>
#include <dlfcn.h>

#include "neural.h"
#include "neural_err.h"

int _get_net_fn( void *net, char *fn_name, void **fn_ptr ) {
  char *error;
  dlerror();
  *fn_ptr = dlsym( net, fn_name );
  error = dlerror();
  if( error ) {
    sprintf_neural_err( "Error resolving %s(): %s", fn_name, error );
    return -1;
  }
  return 0;
}

int load_net( const char *net_file, net_definition *def ) {
  void *net;
  char *error;

  dlerror();
  net = dlopen( net_file, RTLD_NOW );
  error = dlerror();
  if( error ) {
    sprintf_neural_err( "Can't open net SO (%s): %s\n", net_file, error );
    return -1;
  }
  def->dlref = net;

  //load functions from the network SO
  if( _get_net_fn( net, "_net_info", (void **)&def->get_info ) ||
      _get_net_fn( net, "_calc_net", (void **)&def->calculate ) ||
      _get_net_fn( net, "_setup_initial_weights", (void **)&def->setup_weights ) ||
      _get_net_fn( net, "_train_net", (void **)&def->train ) ) {
    //error already set by _get_net_fn() above
    return -1;
  }

  def->get_info( &def->info );
  //maybe let the network set these?
  def->feedback_limit = 1000;
  def->feedback_convergence = 0.05;
  return 0;
}

int init_net_io( net_definition *def, net_io *io, int with_internal_state ) {
  char *fn = "init_net_io";
  io->input_count = 0;
  io->output_count = 0;
  io->node_count = 0;
  io->node_values = NULL; /*this may not otherwise be assigned a value*/
  
  io->inputs = (int *)calloc( def->info.input_count, sizeof(int) );
  if( ! io->inputs ) {
    ERRNO_OUT( fn, "Can't allocate inputs array" );
  }
  io->input_count = def->info.input_count;

  io->outputs = (int *)calloc( def->info.output_count, sizeof(int) );
  if( ! io->outputs ) {
    ERRNO_OUT( fn, "Can't allocate outputs array" );
  }
  io->output_count = def->info.output_count;

  if( with_internal_state ) {
    io->node_values = (double *)calloc( def->info.node_count, sizeof(double) );
    if( ! io->node_values ) {
      ERRNO_OUT( fn, "Can't allocate node values" );
    }
    io->node_count = def->info.node_count;
  }
  return 0;
}

int init_net_weights( net_definition *def, net_weights *weights ) {
  unsigned int seed = 0;
  weights->weight_count = 0;

  weights->weights = (double *)calloc( def->info.weight_count, sizeof(double) );
  if( !weights->weights ) {
    ERRNO_OUT( "init_net_weights", "Can't allocate weights array" );
  }
  weights->weight_count = def->info.weight_count;
  return 0;
}

int starting_weights( net_definition *def, net_weights *weights ) {
  if( 0 > init_net_weights(def,weights) ) {
    //err already set
    return -1;
  }
  return def->setup_weights( weights->weights, weights->weight_count, NULL, 1 );
}
  
void free_net_io( net_io *io ) {
  if( io->inputs && io->input_count ) {
    free( io->inputs );
  }
  if( io->outputs && io->output_count ) {
    free( io->outputs );
  }
  if( io->node_values && io->node_count ) {
    free( io->node_values );
  }
}

void free_net_weights( net_weights *weights ) {
  if( weights->weights && weights->weight_count ) {
    free( weights->weights );
  }
}

int copy_net_io( net_io *dest, net_io *src, int copy ) {
  char *fn = "copy_net_io";
  if( copy & COPY_INPUT ) {
    if( dest->input_count != src->input_count ) {
      ERR_OUT( fn, "dest & source input_count mismatch" );
    }
    memcpy( dest->inputs, src->inputs, sizeof( int ) * dest->input_count );
  }
  if( copy & COPY_OUTPUT ) {
    if( dest->output_count != src->output_count ) {
      ERR_OUT( fn, "dest & source output_count mismatch" );
    }
    memcpy( dest->outputs, src->outputs, sizeof( int ) * dest->output_count );
  }
  if( copy & COPY_INTERNAL ) {
    if( dest->node_count != src->node_count ) {
      ERR_OUT( fn, "dest & source node_count mismatch" );
    }
    memcpy( dest->node_values, src->node_values, sizeof(double)*dest->node_count );
  }
  return 0;
}

int test_io_output( net_io *a, net_io *b ) {
  int i,num_wrong=0;
  if( a->output_count != b->output_count ) {
    return 0;
  }
  for( i = 0; i < a->output_count; i++ ) {
    if( a->outputs[i] != b->outputs[i] ) {
      num_wrong++;
    }
  }
  if( num_wrong == 0 ) {
    return 1;
  } else {
    return num_wrong - a->output_count;
  }
}

int calc_net( net_definition *def, net_io *io, net_weights *weights ) {
  return def->calculate( io->inputs, io->input_count,
			 io->outputs, io->output_count,
			 weights->weights, weights->weight_count,
			 io->node_values, io->node_count,
			 def->feedback_limit, def->feedback_convergence );
}

void train_net( net_definition *def, net_io *io,
		net_weights *weights,
		net_weights *weight_changes,
		double training_level,
		unsigned int flags ) {
  int *correct_outputs = NULL;
  net_weights temp_wght;
  net_weights *wght;
  if( flags & NET_CORRECT_OUTPUTS_GIVEN ) {
    correct_outputs = io->outputs;
  }
  if( flags & NET_ACCUMULATE_WEIGHT_CHANGES ) {
    if( 0 != init_net_weights( def, &temp_wght ) ) {
      return;
    }
    wght = &temp_wght;
  } else {
    wght = weight_changes;
  }
  def->train( weights->weights,
	      wght->weights, wght->weight_count,
	      io->node_values, io->node_count,
	      correct_outputs, io->output_count,
	      def->feedback_limit, def->feedback_convergence,
	      training_level );
  if( flags & NET_APPLY_WEIGHT_CHANGES ) {
    apply_weights( weights, wght );
  }
  if( flags & NET_ACCUMULATE_WEIGHT_CHANGES ) {
    apply_weights( weight_changes, &temp_wght );
  }
}

void apply_weights( net_weights *weights, net_weights *changes ) {
  int i;

  for( i = 0; i < weights->weight_count; i++ ) {
    weights->weights[i] += changes->weights[i];
  }
}

int fwrite_weights( FILE *file, net_weights *weights ) {
  int i;
  char *fn = "fwrite_weights";
  //first, write the number of weights to the file:
  if( 0 > fprintf( file, "%d\n", weights->weight_count ) )
    ERRNO_OUT( fn, "can't write weight_count" );
  //now write the weights:
  for( i=0; i<weights->weight_count; i++ ) {
    if( 0 > fprintf( file, "%0.10e\n", weights->weights[i] ) )
      ERRNO_OUT( fn, "can't write next weight" );
  }
  return 0;
}

int fread_weights( FILE *file, net_weights *weights ) {
  int i,count;
  char *fn = "fread_weights";
  if( 0 > fscanf( file, "%d", &count ) )
    ERRNO_OUT( fn, "can't read weight_count" );
  if( weights->weight_count != count )
    ERR_OUT( fn, "weight_count in file != weight_count in struct" );
  for( i=0; i<count; i++ ) {
    if( 0 > fscanf( file, "%e", weights->weights + i ) )
      ERRNO_OUT( fn, "can't read next weight" );
  }
  return 0;
}

int fwrite_net_io( FILE *file, net_io *io ) {
  int i;
  char *fn = "fwrite_net_io";
  //write the 3 counts out first, so that problems can be detected earlier.
  if( 0 > fprintf( file, "%d\n", io->input_count ) ||
      0 > fprintf( file, "%d\n", io->output_count ) ||
      0 > fprintf( file, "%d\n", io->node_count ) )
    ERRNO_OUT( fn, "can't write header" );
  for( i = 0; i < io->input_count; i++ ) {
    if( 0 > fprintf( file, "%d\n", io->inputs[i] ) )
      ERRNO_OUT( fn, "can't write input" );
  }
  for( i = 0; i < io->output_count; i++ ) {
    if( 0 > fprintf( file, "%d\n", io->outputs[i] ) )
      ERRNO_OUT( fn, "can't write output" );
  }
  for( i = 0; i < io->node_count; i++ ) {
    if( 0 > fprintf( file, "%0.10e", io->node_values[i] ) )
      ERRNO_OUT( fn, "can't write node val" );
  }
  return 0;
}

int fread_net_io( FILE *file, net_io *io ) {
  int i,input_count, output_count, node_count;
  double node_dummy;
  char *fn = "fread_net_io";
  if( 0 > fscanf( file, "%d", &input_count ) ||
      0 > fscanf( file, "%d", &output_count ) ||
      0 > fscanf( file, "%d", &node_count ) )
    ERRNO_OUT( fn, "can't read header" );
  if( io->input_count != input_count ||
      io->output_count != output_count )
    ERR_OUT( fn, "input/output counts don't match file" );
  //handle node count a little differently:
  //if io has no node space, assume client isn't interested in node values.
  //if io has node space but none is in file, that is an error
  if( io->node_count != node_count && io->node_count != 0 )
    ERR_OUT( fn, "node_values wanted, but not supplied by file" );
  for( i = 0; i < io->input_count; i++ ) {
    if( 0 > fscanf( file, "%d", io->inputs + i ) )
      ERRNO_OUT( fn, "can't read input" );
  }
  for( i = 0; i < io->output_count; i++ ) {
    if( 0 > fscanf( file, "%d", io->outputs + i ) )
      ERRNO_OUT( fn, "can't read output" );
  }
  if( io->node_count == 0 ) {
    for( i = 0; i < node_count; i++ ) {
      fscanf( file, "%e", &node_dummy );
    }
  } else {
    for( i = 0; i < io->node_count; i++ ) {
      if( 0 > fscanf( file, "%e", io->node_values + i ) )
	ERRNO_OUT( fn, "can't read node value" );
    }
  }
  return 0;
}



int fread_net_io_set( FILE *file, net_io **set_buf, net_io ***set, int *count, 
		      net_definition *def, int with_internal_state ) {
  int set_count,i;
  net_io *cur, **ptrs;
  char *fn = "fread_net_io_set";
  *count = 0;

  if( 0 > fscanf( file, "%d", &set_count ) ) {
    sprintf_neural_err( "%s: %s: %s", fn, "unable to allocate set arrays", 
			strerror( errno ) ); 
    return -1;
  }

  *set_buf = (net_io *)calloc( set_count, sizeof( net_io ) ); 
  if( *set_buf )
    *set = (net_io **)calloc( set_count, sizeof( net_io * ) );

  if( !*set_buf || !*set) {
    ERRNO_OUT( fn, "unable to allocate set arrays" );
  }
  ptrs = *set;

  for( i=0; i<set_count; i++ ) {
    cur = *set_buf + i;
    //errors below here already set by called functions
    if( 0 > init_net_io( def, cur, with_internal_state ) )
      return -1;
    if( 0 > fread_net_io( file, cur ) )
      return -1;
    (*count)++;
    ptrs[i] = cur;
    
  }
  return 0;
}
