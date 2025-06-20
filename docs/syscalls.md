# System Calls

System Calls are an important phase of any kernel. System Calls allow user-space applications to communicate with the kernel and obtain information or perform actions to the screen, this are done though interrupts.

## Some terms

Some arguments that the syscall expects are:

- `fd`: This is the 'file descriptor' which esentially means **where to output or read from**:
    - `0x0` is the `stdin`
    - `0x1` is the `stdout`
    - `0x2` is the `stderr`
    - `-1` is for `the current pid`
    - **And the rest are user or driver-defined**
- `prot`: These are the **protection flags** used when mapping memory, they essentially indicate which privileges does the mapped memory have.

Note that for compatibility with some libraries and in standard, we mostly use **a modification of the Linux Syscall Table**

## The default system calls

| Syscall name | Code  | Description                                                          | Signature                                                                                                          |
| ------------ | ----- | -------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| read         | `0x0` | Reads a stream of bytes from the specified file descriptor           | `read(fd: usize, buf: [*]u8, count: usize) usize [LEN]`                                                            |
| write        | `0x1` | Writes a stream of bytes to the specified file descriptor            | `write(fd: usize, buf: [*]const u8, count: usize) usize [LEN]`                                                     |
| open         | `0x2` | Creates a file descriptor out of a path in disk                      | `open(path: [*]const u8 (null-terminated), flags: u32, mode: u32) isize [FD]`                                      |
| close        | `0x3` | Destroys and closes a file descriptor                                | `close(fd: usize) isize [STATUS]`                                                                                  |
| proc         | `0x4` | Opens a new process with the executable provided                     | `proc(path: [*]u8 (null-terminated)) usize [PID]`                                                                  |
| exit         | `0x5` | Exits the current process with a code                                | `exit(code: usize) noreturn [-]`                                                                                   |
| getpid       | `0x6` | Obtains the current process id                                       | `getpid() usize [PID]`                                                                                             |
| remove       | `0x7` | Deletes a file in a target path and closes all file descriptors      | `remove(path: [*]const u8 (null-terminated)) isize [STATUS]`                                                       |
| rmdir        | `0x8` | Deletes a directory and its contents and closes all file descriptors | `rmdir(path: [*]const u8 (null-terminated)) isize [STATUS]`                                                        |
| newdir       | `0x9` | Creates a new directory                                              | `newdir(path: [*]const u8 (null-terminated), openfd: usize) isize [FD / STATUS]`                                   |
| rename       | `0xA` | Renames a file. Does not close file nor change file descriptors      | `rename(path: [*]const u8 (null-terminated), name: [*]u8, nameLen: usize) isize [STATUS]`                          |
| memmap       | `0xB` | Maps memory to the process address space                             | `memmap(addr: usize (0 to let kernel decide), len: usize, prot: usize, fd: usize, offset: usize (0)) usize [ADDR]` |
| getunix      | `0xC` | Gets the unix time                                                   | `getunix() u64 [TIME]`                                                                                             |
| version      | `0xD` | Stores the kernel version and name in a buffer                       | `version(buf: [*]u8, len: usize) isize [STATUS]`                                                                   |
