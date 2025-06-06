# System Calls
System Calls are an important phase of any kernel. System Calls allow user-space applications to communicate with the kernel and obtain information or perform actions to the screen, this are done though interrupts.

## Some terms
Some arguments that the syscall expects are:
* `fd`: This is the 'file descriptor' which esentially means **where to output or read from**:
  * `0x0` is the `stdin`
  * `0x1` is the `stdout`
  * `0x2` is the `stderr`
  * **And the rest are user or driver-defined**
* `prot`: These are the **protection flags** used when mapping memory, they essentially indicate which privileges does the mapped memory have.

Note that for compatibility with some libraries and in standard, we mostly use **a modification of the Linux Syscall Table**

## The default system calls
| Syscall name | Code  | Description | Sample Call |
| ----------- | ----------- | --- | ------------- |
| read       | `0x0`       | Reads a stream of bytes from the specified file descriptor | `read(fd: usize, buf: [*]u8, count: usize) usize`
| write  | `0x1`        | Writes a stream of bytes to the specified file descriptor | `write(fd: usize, buf: [*]const u8, count: usize) usize`
| open | `0x2` | Creates a file descriptor out of a path in disk | `open(path: [*]const u8, pathLength: u32, flags: u32, mode: u32) isize` |
| close | `0x3` | Destroys and closes a file descriptor | `close(fd: usize) isize` |
| memmap | `0x9` | Maps a file or memory into the process address space | `memmap(addr: usize, length: usize, prot: u32, flags: u32, fd: usize, offset: usize) usize`
| end | `0x3C` | Ends a process with a specific code | `end(code: usize) noreturn`

## The public variables
There are some variables that are stored in kernel memory, and those are shared with system-calls. Here's the record:
* `0xC1000010` is the **Framebuffer Terminal**