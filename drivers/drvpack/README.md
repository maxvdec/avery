# The Avery Driver Format Tooling

We provide some tooling to help you transform your arf files into valid **drivers**.

## How to use?

To use the tooling simple run this command.

```bash
drvpack object.dro -o mydriv.drv
```

This will prompt you to the following questions:

- What's the name of your driver?
- Describe your driver in a sentence
- What version is your driver in?
- Introduce the manufacturer ID (default 0)
- Introduce the device ID (default 0x0)
- Introduce the subsystem ID (default 0x0)
- Type in the type ID (default 'Empty Driver (0)')

To make things more automatic and easy, you can put the answers in a text file, separate the answers with `\n` and submit it to the command:

```bash
drvpack object.dro -o mydriv.drv -d answers.txt
```
