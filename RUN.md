# How to run the Avery Kernel

The first thing you need is to install **qemu**, which is a virtual machine. We haven't test this in real hardware yet, but you should be able to flash the ISO into an external USB drive or CD and boot from there.

## How to setup the enviroment

Prepare the enviorment for running the kernel. You should have two things in order to run the kernel properly.

- A Disk where you can store data. This can be created as follows:
  First, **compile and put somewhere accessible the ionicfs tooling** and use these commands:

    ```bash
    dd if=/dev/zero of=disk.img bs=1M count=512 # This creates a disk of 512Mb
    ionicfs format disk.img # Follow the processs
    ```

- Then, you need the iso. Download it or create it as stated [here](./BUILD.md)

## How to run the kernel

Finally, just type in: `make run` and that will run in a QEMU virtual machine the `avery.iso` with the `disk.img` file. If your files are named differently, use the following command:

```bash
qemu-system-x86_64 -drive file=<disk path>,format=raw -cdrom <iso path> -m 128M -boot d -serial stdio
```
