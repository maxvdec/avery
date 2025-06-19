# The Avery Kernel

The Avery Kernel is a versatile, fast, and modern kernel written in Zig for the modern era, it is totally open-source and it aims to be the kernel for the XXI century.

# Features

- Fast boot
- GRUB booting
- VGA Interface
- Memory management
- Powerful interrupt system

## Roadmap (To Alpha)

I expect to add some things to this kernel before droping an alpha:

- [x] Drivers for basic file systems _(FAT32, VFS)_
- [ ] Simple USB Capabilties
- [ ] Audio Support
- [ ] A new shell _(Fusion)_
- [ ] Networking capabilities
- [x] User and Kernel Space
- [x] Executable execution
- [ ] Custom bootloader _(Rouge)_
- [ ] System Calls **Work in progress**
- [ ] Support for more architectures
- [ ] Add support for driver management **Work in progress**
- [ ] Create a standard library (libc)
- [x] Add process schedueling
- [ ] Support multi-threading
- [x] Support multiple process executing at the same time
- [ ] Configure start processes
- [ ] Add better kernel logging

Then, We will expand the kernel to add more functionalities until make Avery, the modern successor of Linux.

# Some interesting documents

- [Build](./BUILD.md) teaches you how to build all the software
- [Run](./RUN.md) teaches you how to run the ISO
- The documentation is [here](./docs)
- Also, the license is [here](./LICENSE)
