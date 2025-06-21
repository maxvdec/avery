# The Directory Structure

Avery follows a custom way to organize the directories and files required by the system to work. These are normally part of **mOS**. For people developing Operating Systems without mOS, note that you can change the routes by editing [the following file](../kernel/userland/dir_structure.zig).

## The Default Structure

- `/System` contains the main files that the system needs to function

## The System Directory

- `/System/Avery` contains the kernel
- `/System/mOS` contains the OS (can be changed)
- `/System/Drivers` contains all the drivers that are going to be executed at init
- `/System/Applications` contains the applications installed system-wide
- `/System/Binaries` contains the programs
