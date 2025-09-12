# Contribution Guides

Welcome to the Avery Kernel development community. This document is a guide on how to help to make Avery a great and powerful kernel. Thus, we would like to kindly ask you to maintain certain aspects and follow simple rules to help everyone stay organized.

First, read our [Code Of Conduct](CODE_OF_CONDUCT.md) for more information on how to respect and take care of the development community.

## Suggest changes

One important aspect of contribution is speaking with the developers about what is wrong, or which features would you like to have in the kernel:

- For problems, bugs, minor changes, or structured changes create **an Issue** here in GitHub. Pair it with a tag, and follow the proposed instructions in the template.

- For proposals, create **a Discussion**, we check them so we can hear about what needs to be changed. From there, we'll create the corresponding issues for developers to know what has to be done

## What are we working on?

The `main` branch contains the **latest development state** of the kernel. For releases check the branches called `release/vX.X`. Also, for development purposes, we'll create branches that symbolize different development aspects. Our **roadmap** is available on our [readme](README.md)

# How to structure a branch

We assume you know how to fork a repo and get started with modifying Delta. Besides that, we have a strong policy about naming branches, so we can have our repo structured:

* Feature branches (the ones that implement new features) are prefixed with `feature/`
* Fix branches (from minor to big fixes) are prefixed with `fix/`
* Program branches (reorganization of files, optimizations, things that are not seen by the user) are prefixed with `program/`
* Repo branches (changing files for the repo structure, GitHub actions...) are prefixed with `repo/`
* Documentation branches (adding documentation) are prefixed with `doc/`
* Long-living branches (releases, etc...) aren't prefixed, these are rare

# How to get your Pull Request to be accepted
* Make sure all the tests are passing, use the commands in the `.github/workflows` to test the result
* Make sure to document every public part of the code, so other developers can understand
* In the Pull Request body, explain the changes clearly

## How to get inspiration

You can check the issues every now and then. If you can, try checking the ones with the **needed** tag, meaning they are neaded by the community.