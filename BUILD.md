# Build Instructions

## How to build the Kernel

### In macOS

Make sure you have the following dependencies installed:

```
xorisso zig make x86_64-elf-binutils nasm
```

and download and compile from source [grub](https://git.savannah.gnu.org/git/grub.git). Also, if you want build instructions for grub, check this [gist](https://gist.github.com/emkay/a1214c753e8c975d95b4).

Then, just type `make`.

This process should create a `avery.iso` file. Then, follow the instructions [here](./RUN.md).

### In Linux

Make sure you have the following dependencies installed:

```
xorisso zig make grub-common nasm
```

Note that if you are in an ARM enviorment, you have to get a cross-compiler. Once all is installed, proceed by typing `make`. This, should generate a `avery.iso` file. Then, follow the instructions [here](./RUN.md)

### In Windows

To compile in Windows, you should install WSL (Windows Subsystem for Linux) and basically follow the steps there.

## How to build the Ionic FS tooling

In order to build the Ionic FS tooling, install the following dependencies:

```
cmake
```

Once CMake is installed, use the `cmake .` command, and then `make` to produce the final binary. Move that binary somewhere that is tracked by the `$PATH` variable in your system, for instance `/usr/local/bin` or `/system/binaries` in Avery.

## How to build the drivers and ARF tooling

For that, you'll need to install **Rust**. Once **cargo** is installed, go to the respective folder and use `cargo build --release`. The output will be at `./target/release/`. Once that is done, copy the result to a folder in your path.
