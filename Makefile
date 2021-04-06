.PHONY: all
all:
	./compile-git-with-openssl.sh --skip-tests --build-dir=./build


.PHONY: clean
clean:
	-rm -rf ./build
