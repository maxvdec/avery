# Ionic FS

Ionic FS is a File System we designed to be easy, while offering powerful features.
It is a File System designed to be used as one of the available ones on the Avery Kernel.

**This is a basic filesystem, it is not roughly reccommended to use it as your main filesystem.**<br>
**Note that the filesystem uses big endian to store the data**<br>

## Tooling
We made some crossplatform tooling in C++ for reading, writing and formating Ionic disks.
* `ionicfs format <disk>`: Will guide you thought the process of formatting a disk image.
* `ionicfs pathExists <disk> <path> [partition_index]`: Will inform if the path exists and list its contents.
* `ionicfs list <disk> <path> [partition_index]`: Will list the contents of directory.
* `ionicfs read <disk> <path> [partition_index]`: Will read a file from the disk.
* `ionicfs read -hex <disk> <path> [partition_index]`: Will *hexdump* the file from the disk.
* `ionicfs copy <disk> <path> <file> [partition_index]`: Will copy the file into some path.
* `ionicfs mkdir <disk> <path> [partition_index]`: Will create a new directory
* `ionicfs rm <disk> <path> [partition_index]`: Will remove a file from the disk.
* `ionicfs rm-dir <disk> <path> [partition_index]`: Will remove a directory and its subcontents from the disk.
* `ionicfs info <disk>`: Will print some information about the disk.
* `ionicfs boot <disk> <binary>`: Will overwrite the boot-code of the disk to the one in the binary

## Specifications
Each disk is divided into 512 byte chunks named **regions**, each region has its own *LBA (Logical block address)*.
Thus, each block contains some data that we must interpret in some way.

### The first region
The first region is called the **preface** since it introduces some information that is useful to the system.
* The first **400** are designed to be the **boot code**. This will be used to boot from the disk. 
* Then we have **26** bytes per partition *(104 in total)*, adding 4 partitions. They are splitted this way:
  * The first **18** bytes are for the *Partition Name*, ending with `\0`, so 17 characters.
  * Then we have **4** bytes *read as a uint32* that indicate the *Partition Region Number*. **If the partition region number is 0, it means the partition is unusable**
  * Then the last **4** bytes *also read as a uint32*, indicate the *Partition Size* in regions.
* Then the last **8** bytes are a *Sanity Check*. You must make sure it matches the string `IONFS<major><minor><minor>`
 
### How to read a partition
When you jump to the address of a partition, you are in its **Root Directory**, so you are basically going to read a directory.
It is important that when you read a region, these bytes match:

* The **first byte** is the **type byte** and it dictates the type of region we're reading:
  * `0x0` is an **empty region**. You can overwrite it freely
  * `0x1` is a **deleted region**. You can overwrite it, make sure to overwrite it entirely
  * `0x2` is a **directory region**. It is a directory
  * `0x3` is a **file region**. It part of a file<br>
  * `0x4` is a **disk reference**. It **symbolizes** a new type of disk.
* The last **four bytes** are called the **next** and it gives information on where to go:
  * `0x0` is an **end**. It mean the directory or the file is ended. All the data is read.
  * `<sec.>` is the next sector you should jump if the next is not end. Is where the directory or file continues
 
### How to read a directory
Firstly, make sure that the first byte is `0x2` for a directory region. A directory is just a list of structured **Directory Entries**. These follow this structure:
* The **first byte** is the **type byte**, and following the guide from before, you can see the type of the file: whether it's empty, deleted, a directory or a file, just adding the `0x00` type, which in this context means it's the **end of the directory**
* The following **24 bytes** are reserved for some useful times. These bytes are divided into:
  * 8 bytes (`uint64`), that represent the **last time the file was accessed**
  * 8 bytes (`uint64`) that represent the **last time the file was edited**
  * 8 bytes (`uint64`) that represent the **time when the file was created**.
* Then you should read the filename upto finding a null byte `\0`. This name contains indeed the extension of the file, e.g. `test.txt`
* Then, we read the following **4 bytes** as a `uint32` to know where we should go to read that entry.
* The last **4 bytes** of the region are the **end** and follow the same guidelines as established before. **Just directory entries can be splitted, but their inner structure can't. That means you will not have to read the file name or other metadata through different regions. You must make sure you have enough space available to fit the entry**

### How to read a file
Reading a file is easy, you just parse the regions until you get to a region where it ends with `0x0`. 

### How to read a disk reference
This is OS dependent, but you should read the four bytes and based on the value switch to a disk or another.
Routes aren't kept the same. It is just meant to get the name of the disk, nothing else!