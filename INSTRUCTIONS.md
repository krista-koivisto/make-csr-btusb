## 1. Download the linux-stable source and switch to the correct branch

Download the source:

```Bash
git clone git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git
```

Switch to the correct branch:

```Bash
cd linux-stable
BTU_KERNEL_VERSION=$(uname -r | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+')
BTU_KERNEL_REVISION=$(echo "$BTU_KERNEL_VERSION" | grep -Eo '[0-9]+$')
if [ "$BTU_KERNEL_REVISION" == "0" ]; then
    BTU_KERNEL_VERSION=$(echo "$BTU_KERNEL_VERSION" | grep -Eo '[0-9]+\.[0-9]+')
fi
git checkout -B "btusb$BTU_KERNEL_VERSION" $(git tag -l | grep -E "$BTU_KERNEL_VERSION\$")
```

## 2. Patch the `drivers/bluetooth/btusb.c` file

  * `bcdDevice == 0x8891` - Corresponds to CSR firmware version
  * `le16_to_cpu(rp->lmp_subver) == 0x1113`

Either do it using this quickie:

*Make sure you are in `linux-stable` for this part.*

```Bash
sed -i "s/bcdDevice <= 0x100 || bcdDevice == 0x134)/bcdDevice <= 0x100 || bcdDevice == 0x134 || bcdDevice == 0x8891)/" "drivers/bluetooth/btusb.c" && sed -i "s/le16_to_cpu(rp->lmp_subver) == 0x0c5c)/le16_to_cpu(rp->lmp_subver) == 0x0c5c ||\n	    le16_to_cpu(rp->lmp_subver) == 0x1113)/" "drivers/bluetooth/btusb.c"
```

Or if that doesn't work, try to apply the patches manually by changing the two following sections:

```C
if (le16_to_cpu(rp->manufacturer) != 10 ||
    le16_to_cpu(rp->lmp_subver) == 0x0c5c)

[...]

if (bcdDevice <= 0x100 || bcdDevice == 0x134)
```
To
```C
if (le16_to_cpu(rp->manufacturer) != 10 ||
    le16_to_cpu(rp->lmp_subver) == 0x0c5c ||
    le16_to_cpu(rp->lmp_subver) == 0x1113)

[...]

if (bcdDevice <= 0x100 ||
    bcdDevice == 0x134 ||
    bcdDevice == 0x8891)
```

## 3. Preparing the sources

First we prepare the Linux sources for compiling by copying the config from your current kernel to make sure the new module will be compatible.

Make sure you are in the `linux-stable` directory at this point.

```Bash
make mrproper
cp /lib/modules/$(uname -r)/build/.config ./
cp /lib/modules/$(uname -r)/build/Module.symvers ./
```

Now we can make the config. The `olddefconfig` target automatically chooses for you, we don't need to worry about anything like that for our module.

```Bash
make olddefconfig
```

Now we can finally go ahead and prepare the modules for compilation.

We need to get the current kernel's EXTRAVERSION for this. It is required to make sure the module can be loaded without forcing.

```Bash
make EXTRAVERSION=$(grep "EXTRAVERSION = " "/lib/modules/`uname -r`/build/Makefile" | awk '{print $3}') modules_prepare
```

If you don't want to try to get your EXTRAVERSION or if you run into trouble finding it, you can alternatively load the module using the `--force-vermagic` modprobe switch later.

## 4. Compiling

*Make sure you are in `linux-stable` for this part.*

This is the easy part.

```Bash
make -C "/lib/modules/$(uname -r)/build/" M=$(pwd)/drivers/bluetooth modules
```

## 5. Install and insert new module

*Make sure you are in `linux-stable` for this part.*

Before we install the new module, make sure to make a backup of your old one!

```Bash
cp -pf "/lib/modules/$(uname -r)/kernel/drivers/bluetooth/btusb.ko"* ~/
```

Now that we have that out of the way, let's finally install and insert it.

First, we need to check the compression method your current kernel uses for kernel objects. The easiest way is to just run:

```Bash
find /lib/modules/`uname -r`/kernel/drivers/bluetooth -maxdepth 1 -regextype egrep -regex ".*/btusb\.ko\.?(gz|xz)?" -print -quit | grep -Eo "[a-z]+$"
```

Take the next step based on the output of that command:
* `ko` - No compression is used, move to the next step
* `gz` - Gzip compression, run `gzip drivers/bluetooth/btusb.ko`
* `xz` - xz compression, run `xz -f drivers/bluetooth/btusb.ko`

Finally let's install it by replacing the old module with the new one (make sure you backed the old one up first!):

```Bash
sudo cp -f "drivers/bluetooth/btusb.ko"* "/lib/modules/$(uname -r)/kernel/drivers/bluetooth/"
```

Now let's remove the old module and insert the new one:

```Bash
sudo modprobe -r btusb
sudo modprobe btusb
```

Done! Enjoy your Bluetooth module!
