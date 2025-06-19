# The Avery Driver Format - 0.1

Drivers are an important part of the system. They are responsible for handling various parts of the system and provide interfacing for other things like external peripherals and modify and extend the kernel. Drivers are what are called **kernel modules** in other systems. [mOS](https://github.com/maxvdec/mOS) offers the most common drivers for standard usecases, within a collection named **Aspire**.

## How to compile drivers

Drivers are packed in an special format called **The Avery Driver Format**. These have the `.drv` extension asociated to them. Drivers are usually made with C, but the language can be whatever language the developer desires, although it should have C compatibility since kernel functions are defined in a C header.

First, locate the `avery.h` file in your machine and add it to your path or just add it to your editor, so its aware of it. Then, write a simple driver:

```c
#include <avery.h>

// Here, you should initialize everything you need to handle events.
avery_status init(u32 driverId) {
    avprint("Hello, World!\n");
    avprint("This message is print at driver: ");
    avprintn(driverId);
    avprint("\n");
    return AVERY_OK;
}

// Here, you should deallocate and stop all services you've initiliazed
avery_status destroy() {
    return AVERY_OK;
}
```

Note that **drivers run in kernel mode**. So, you **must be careful with errors and handle them correctly** to avoid crashing the user computer.

To compile the driver, use whatever compile you have available. For instance:

```bash
gcc -c my_driver.c -I /Path/To/AveryH/Directory -o elf_object.o -m32
arf translate elf_object.o -o arf_object.dro
```

The `.dro` file is just a **regular ELF object** but intended to be used as an alias to indicate that the object represents a driver.

Then, use the driver packer tool provided in the [mOS repository](https://github.com/maxvdec/mOS) to pack the driver accordingly. When packing it'll ask a couple of questions. Here's an example

```
> ./drvpack arf_object.dro -o mydriv.drv
Welcome to the Avery System Driver Packer.
We'll ask you some questions in order to determine and pack the driver with the corresponding flags.

- What's the name of your driver?
> CoolDriver

- Describe your driver in a sentence
> A simple driver to teach driver creation

- What version is your driver in?
> 1.0.0

- Introduce the manufacturer ID (default 0x0)
>
(using 0x0)

- Introduce the device ID (default 0x0)
>
(using 0x0)

- Introduce the subsystem ID (default 0x0)
>
(using 0x0)

- Type in the type ID (default 'Empty Driver (0)')
> 0

Packing driver...

Driver packed!
```

Then you have a couple of options. For now, copy the file to the `/System/Drivers` folder and it'll be executed at login.

## The Format

We've created an special format for dealing with drivers. This format is easy to read:

### The Header

The header is a simple array of bytes that indicate the format. In this case, we find eight bytes: `AVDRIVxx`. Where `x` are numbers and represent the version (`AVDRIV01` would correspond to the version **0.1**).

### The configuration types

Then we should continue to read the configuration bytes in this order:

- First we read the **type byte**
- Then we read the **manufacturer ID (2 bytes)**
- Then we read the **device ID (2 bytes)**
- Then we read the **subsystem ID (1 byte)**

### The names

Then we can read some titles and description of the driver:

- First comes the **driver name**, null-terminated
- Then it comes the **driver description**, null-terminated
- Then it comes the **driver version (3 bytes [major, minor, minor])**

### The hash

To ensure security, we provide a hash of the following values concatenated, null-terminated:

- The **name** (not null-terminated)
- The **manufacturer ID** (not null-terminated)
- The **code** (not null-terminated)

### The data

Finally, read the rest of the file as an **ARF executable** (more on that [here](./arf.md))

## The Driver Types

Each driver type is specified to **export certain functions** to interface with the operating system. Each type has an identifier. There are two **standard fuctions** that every type should have:

```c
avery_status init(u32 driverId) {}
avery_status destroy() {}
```

### The Empty Driver (0x0)

This type only requires the default functions to be provided (`init()` and `destroy()`).

### The Stream Driver (0x1)

This driver is meant to be used with devices that feature both **input and output** such as: mice, keyboard and more...

```c
// Should initialize the device
avery_status init(avery_device* dev, u32 driverId) {}

// Should close the device
avery_status destroy(avery_device* dev) {}

// Should read from the device
avery_status read(avery_device* dev, void* buffer, size_t count) {}

// Should write to the device
avery_status write(avery_device* dev, const void* buffer, size_t count) {}

// Should send a command to the device
avery_status sendcmd(avery_device* dev, u32 cmd, void* arg) {}

// Checks if read / write would block the device
bool poll(avery_device* dev);

// Maps mempory or registers for the device
avery_buf memmap(avery_device* dev, size_t len, u64 offset) {}
```

### The Block Device (0x2)

This driver handles block-oriented storage devices like hard drives, SSDs or USB drives. Manages sector-based I/O and it sends specific commands.

```c
// This function should initialize the driver. Flags can be interpreted as wish
avery_status init(avery_stg* dev, int flags, u32 driverId) {}

// This function should close the device.
avery_status destroy(avery_stg* dev) {}

// Should read the sector and store the value in the buffer
avery_status read(avery_stg* dev, u64 sector, void* kbuffer, size_t count) {}

// Should write the data over to the sector
avery_status write(avery_stg* dev, u64 sector, const void* data, size_t count) {}

// Should send the command to the device
avery_status sendcmd(avery_stg* dev, u32 cmd, void* arg) {}
```

### The Filesystem Plugin (0x3)

This driver helps translate the one filesystem over to data that the kernel can undestand. Can be used to bring other filesystems over to Avery.

```c
// This function should return information about the filesystem and initialize it.
avery_fs init(avery_device* dev, u32 driverId) {}

// This function should free memory and close the device.
avery_status close(avery_device* dev) {}

// This function should read from a path
avery_status read(avery_device* dev, const char* path, void* buf) {}

// This function should create a file or directory
avery_status create(avery_device* dev, const char* path, bool directory) {}

// This function should delete a file or directory
avery_status delete(avery_device* dev, const char* path, bool directory) {}

// This function should write to a file
avery_status write(avery_device* dev, const char* path, const void* buffer) {}

// Get statistics about the filesystem
avery_fstat getstats(avery_device* dev) {}
```

### The Memory Technology Device (0x4) [NOT IMPLEMENTED]

### The Network Interface (0x5) [NOT IMPLEMENTED]

### The Protocol Stack (0x6) [NOT IMPLEMENTED]

### The Terminal / Serial Output (0x7) [NOT IMPLEMENTED]

### The PCI Driver (0x8) [NOT IMPLEMENTED]

### The USB Driver (0x9) [NOT IMPLEMENTED]

### The Audio Driver (0xA) [NOT IMPLEMENTED]

### The Video Graphics Driver (0xB) [NOT IMPLEMENTED]

### The Input Driver (0xC) [IN PROGRESS]

### The Human Interface Device Driver (0xD) [IN PROGRESS]

### The Power Supply Driver (0xE) [NOT IMPLEMENTED]

### The Thermal Driver (0xF) [NOT IMPLEMENTED]
