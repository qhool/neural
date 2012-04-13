CFLAGS=-g -I ../include
LDFLAGS=-L ../lib -lneural

all: train_and_evaluate

update: all
	cp train_and_evaluate ../bin
	cp *.pl ../bin

clean:
	-rm *.o
	-rm train_and_evaluate