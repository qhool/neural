nets=$(wildcard *.net)
cs=$(subst .net,.c,$(nets))
libs=$(subst .net,.so,$(nets))

CFLAGS=-I ../include -g

ifeq ($(shell uname), 'Linux')
	NETFLAGS=-ldl
endif

all: $(cs) $(libs)

%.so: %.o
	$(CC) -lm $(NETFLAGS) -shared -o $@ $<

%.c: %.net
	./compile.pl $< $@

clean: FORCE
	-rm *.so *.c

FORCE: