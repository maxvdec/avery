# Tests for the thery Kernel
These are some tests we wrote during the course of the development of Avery. These are made with assembly and C, and they're useful to test various things of the OS. 

## How to rum them
First, you must compile them for the architecture you want (make sure Avery supports). Then, use the `arf` tool over in `/tools/arf` (written in Rust) and use the following command:
```
arf myElf -o myArf.arf -d theTestDescriptor.ad
```
Make sure to compile the files with their corresponding description file. When compiling them, make sure the **entry point** is `main` (`-e main`)