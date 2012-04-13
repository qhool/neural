#ifndef __NEURAL_ERR_H
#define __NEURAL_ERR_H

#include <errno.h>
#include <string.h>

void set_neural_error( char *description );
void sprintf_neural_err( char *format, ... );

#define ERR_OUT( fn_name, err ) { sprintf_neural_err( "%s: %s", fn_name, err ); return -1; }

#define ERRNO_OUT( fn_name, err ) { sprintf_neural_err( "%s: %s: %s", fn_name, err, strerror( errno ) ); return -1; }

#endif /* __NEURAL_ERR_H */
