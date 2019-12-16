# What is this?

This is a Bash shell script for compiling a custom `btusb` kernel module for Linux.

# What does it do?

It replaces the `btusb` kernel module with one compatible with some Bluetooth 5.0 "CSR" devices. It does this as follows:

* Downloads the linux-stable source (using git clone from kernel.org)
* Patches the `drivers/bluetooth/btusb.c` file in place, adding in two new options for conditional statements:
    * `bcdDevice == 0x8891` - Corresponds to CSR firmware version
    * `le16_to_cpu(rp->lmp_subver) == 0x1113`
* Compiles the module
* Backs up old module and replaces with new
* (Optional) Runs `modprobe` to insert new module

# Is that really a good idea?

## Probably not

Automating the process of patching source code for kernel modules is generally not the best way to go about things.

I wrote this script to save time for myself until the kernel gets improved support for CSR Bluetooth devices. That said, others are of course free to use it at their own risk.

## Do it manually instead

Read INSTRUCTIONS.md file for step-by-step instructions on building your own module.

# Tested Distributions

## Ubuntu 18.04 LTS

The following command snippet worked on a fresh Ubuntu 18.04 LTS:

```sudo apt update && sudo apt -y install git make linux-headers-$(uname -r) build-essential flex bison libssl-dev libelf-dev && ./make-install-btusb.sh```

## Manjaro

The script has also been tested in Manjaro Linux where it worked without modification, but the system was not a new install and as such some packages may already have been installed.

```sudo pacman -Syu git make linux-headers bison base-devel bc```

# Compatible kernels

The script has been tested on kernels 4.9.206, 5.0.0 and 5.4.2 and is possibly compatible with all kernels inbetween, probably even some earlier ones and some future ones as well.

# Support

No support will be given for this script due to the complexity of automating the process of patching and compiling kernel module source code.

Only use this script if you know what you are doing, otherwise it is better to just wait for the `btusb` drivers to be improved or to let a friend do it for you (on their own system).
