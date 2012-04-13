#include <stdarg.h>
#include <stdio.h>

#include "neural.h"
#include "neural_err.h"

char neural_errstr[1024];

void set_neural_error( char *description ) {
  strncpy( neural_errstr, description, 1024 );
}

void sprintf_neural_err( char *format, ... ) {
  va_list args;
  va_start( args, format );
  vsnprintf( neural_errstr, 1024, format, args );
  va_end( args );
}

char *neural_error() {
  return neural_errstr;
}
