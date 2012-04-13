all: update networks

networks: FORCE
	cd networks && $(MAKE)

update: toplevelclean FORCE
	cd neural && $(MAKE) update
	cd src && $(MAKE) update
	cd tools && $(MAKE) update

clean: toplevelclean FORCE
	cd neural && $(MAKE) clean
	cd src && $(MAKE) clean
	cd networks && $(MAKE) clean

toplevelclean: FORCE
	-rm ./include/*
	-rm ./lib/*
	-rm ./bin/*

FORCE:
