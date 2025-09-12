
default:
    just build 

build:
    make clean
    make

run:
    make clean
    make run

lint:
    zig build
    cargo check 
    cd tools/ionicfs && cmake . && make