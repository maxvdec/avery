# The Kernel Extensions
Kernel Extensions are extensions that allow you to perform certain system calls. Avery follows a principal of **just loading what you need**. Normally, the program won't be prepared for using all that the kernel has to offer, and **kernel extensions** are modular and you can request them as you need. Some, although are **fast-loading** kernel extensions, which will **always** be loaded because they're the most used ones. Here's a list of **all** kernel extensions:

| Extension Name | Code | Fast-Loading |
| -------------- | ---- | ------------ |
| console   | 0x00 | Yes           |
| framebuffer        | 0x01 | Yes          |
| filesystem | 0x02 | No |