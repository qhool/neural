CC=gcc
CFLAGS=-g -I ./include

ifeq ($(shell uname), Linux)
	NEURALFLAGS=-ldl
endif
 
all: libneural.so

libneural.so: neural.o sets.o error.o
	$(CC) neural.o sets.o error.o $(NEURALFLAGS) -shared -o libneural.so 

update: all FORCE
	cp libneural.so ../lib
	cp include/neural.h ../include

clean: FORCE
	-rm *.so
	-rm *.o

FORCE:
