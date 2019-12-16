#!/bin/bash
#
# Downloads stable kernel sources and compiles a custom module for it.

# Install when done making module?
# Requires super user privileges.
#
# Manual installation:
# sudo cp -f "linux-stable/drivers/bluetooth/btusb.ko.xz" "/lib/modules/$(uname -r)/kernel/drivers/bluetooth"
DO_INSTALL=1

# Linux headers location
LINUX_HEADERS="/lib/modules/$(uname -r)/"

# Linux kernel build base (under LINUX_HEADERS, typically 'build' or 'kernel')
KERNEL_BUILD_BASE="build"

# Log file to write output to
LOG_FILE="$(pwd)/$0.log"

# ============================
# Don't touch below this line.
# ============================

# Hard reset kernel sources?
KERNEL_RESET=0

# Directory under linux-stable where the module is located
KERNEL_DIRECTORY="drivers/bluetooth"

# Module to be compiled and replaced
MODULE="btusb"

# Keeps track of module name (changes during execution)
MODULE_FILE="btusb.ko"

# Timestamp used for files
TIMESTAMP=`date +%s`

acquire_kernel_sources () {
	echo "Starting $0 at $(date)..." > "$LOG_FILE"
	echo "[*] Downloading linux-stable kernel sources from git.kernel.org..."

	if [ -d "linux-stable" ]; then
		echo "[*] You already have a linux-stable directory, possibly from a previous install."
	        echo "[?] A git reset on the source may be necessary if your kernel version has changed."
		read -p "    Perform the recommended reset? [Y/n] " DO_RESET
		
		if [ "${DO_RESET,,}" == "n" ] || [ "${DO_RESET,,}" == "no" ]; then
			echo "[!] Continuing without resetting sources. If your kernel version has changed, a reset may be necessary."
		else
			KERNEL_RESET=1
		fi
	else
		echo "[*] Cloning kernel.org git repository... This might take a few minutes."
		git clone git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git >> "$LOG_FILE"
	fi

	if [ -d "linux-stable" ]; then
		pushd linux-stable > /dev/null
		
		# Reset
		if [ $KERNEL_RESET -eq 1 ]; then
			echo "[*] Running 'git reset --hard' to reset kernel sources."
			git reset --hard >> "$LOG_FILE" >> "$LOG_FILE"
		fi

		# Create branch
		KERNEL_VERSION=$(uname -r | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+')
		KERNEL_REVISION=$(echo "$KERNEL_VERSION" | grep -Eo '[0-9]+$')

		# If kernel is not a revision, but a new release, leave out the revision number
		if [ "$KERNEL_REVISION" == "0" ]; then
			echo "[*] Found kernerl with revision number 0, adjusting version."
			KERNEL_VERSION=$(echo "$KERNEL_VERSION" | grep -Eo '[0-9]+\.[0-9]+')
		fi

		echo "[*] Getting tag for kernel $KERNEL_VERSION"
		GIT_KERNEL_TAG=$(git tag -l | grep -E "$KERNEL_VERSION\$")
		echo "[*] Creating/resetting branch $MODULE$KERNEL_VERSION"
		git checkout -B "$MODULE$KERNEL_VERSION" "$GIT_KERNEL_TAG" >> "$LOG_FILE"

		popd > /dev/null
		
		echo ""
		echo "[*] Kernel sources ready."
		echo ""
	else
		echo ""
		echo "[#] ERROR: linux-stable kernel wasn't downloaded, unable to continue. To fix, please manually download the latest stable kernel to this directory using:"
		echo "git clone git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git"
		echo ""
		exit 1
	fi
}

prepare_for_compilation () {
	echo "[*] Preparing kernel sources for module compilation..."
	pushd "linux-stable" > /dev/null

	echo "[*] Running 'make mrproper' to clean kernel source tree and configs."
	make mrproper >> "$LOG_FILE"

	echo "[*] Copying config files from system."
	cp "$LINUX_HEADERS/$KERNEL_BUILD_BASE/.config" ./
	cp "$LINUX_HEADERS/$KERNEL_BUILD_BASE/Module.symvers" ./

	echo "[*] Running 'make olddefconfig' to set default options based on config files."
	make olddefconfig >> "$LOG_FILE"

	EXTRAVERSION=$(grep "EXTRAVERSION = " "$LINUX_HEADERS/${KERNEL_BUILD_BASE}/Makefile" | awk '{print $3}')
	echo "[*] Kernel has EXTRAVERSION: '$EXTRAVERSION', running 'make modules_prepare' with that in mind."
	echo "    This step might take a minute..."
	make EXTRAVERSION="$EXTRAVERSION" modules_prepare >> "$LOG_FILE"

	popd > /dev/null

	echo ""
	echo "[*] Done preparing!"
	echo ""
}

patch_module () {
	echo "[*] Backing up $MODULE.c to ${TIMESTAMP}_$MODULE.c before patching."
	cp -f "linux-stable/$KERNEL_DIRECTORY/$MODULE.c" "${TIMESTAMP}_$MODULE.c"

	echo "[*] Attempting to patch $MODULE.c."
	BCD_DEVICE_OLD="bcdDevice <= 0x100 || bcdDevice == 0x134)"
	BCD_DEVICE_NEW="bcdDevice <= 0x100 || bcdDevice == 0x134 || bcdDevice == 0x8891)"
	sed -i "s/$BCD_DEVICE_OLD/$BCD_DEVICE_NEW/" "linux-stable/$KERNEL_DIRECTORY/$MODULE.c"

	SUBVER_OLD="le16_to_cpu(rp->lmp_subver) == 0x0c5c)"
	SUBVER_NEW="le16_to_cpu(rp->lmp_subver) == 0x0c5c ||\n	    le16_to_cpu(rp->lmp_subver) == 0x1113)"
	sed -i "s/$SUBVER_OLD/$SUBVER_NEW/" "linux-stable/$KERNEL_DIRECTORY/$MODULE.c"

	echo "[*] Verifying patch...."
	PATCH_RESULT_1=$(cat "linux-stable/$KERNEL_DIRECTORY/$MODULE.c" | grep "bcdDevice == 0x8891")
	PATCH_RESULT_2=$(cat "linux-stable/$KERNEL_DIRECTORY/$MODULE.c" | grep "le16_to_cpu(rp->lmp_subver) == 0x1113")

	if [ ${#PATCH_RESULT_1} -gt 0 ] && [ ${#PATCH_RESULT_2} -gt 0 ]; then
		echo "[*] Patch passed check."
	else
		echo "[#] ERROR: Seems like the patch failed to apply correctly. Unable to continue!"
		exit
	fi
}

make_module () {
	if [ -d "linux-stable/$KERNEL_DIRECTORY" ]; then
		echo "[*] Compiling modules in $KERNEL_DIRECTORY."
		echo "    This will take a minute, but we're almost done!"

		pushd "linux-stable/$KERNEL_DIRECTORY" > /dev/null
		make -C "/lib/modules/$(uname -r)/$KERNEL_BUILD_BASE/" M=$(pwd) clean >> "$LOG_FILE"
		cp "/lib/modules/$(uname -r)/$KERNEL_BUILD_BASE/.config" ./ >> "$LOG_FILE"
		cp "/lib/modules/$(uname -r)/${KERNEL_BUILD_BASE}/Module.symvers" ./ >> "$LOG_FILE"
		make -C "/lib/modules/$(uname -r)/$KERNEL_BUILD_BASE/" M=$(pwd) modules >> "$LOG_FILE"
		echo "[*] Done compiling!";
		popd > /dev/null

		echo "[*] Checking module compression method."
		COMPRESS_METHOD=$(find /lib/modules/`uname -r`/kernel/"$KERNEL_DIRECTORY" -maxdepth 1 -regextype egrep -regex ".*/$MODULE\.ko\.?(gz|xz)?" -print -quit | grep -Eo "[a-z]+$")

		if [ "$COMPRESS_METHOD" == "xz" ]; then
			echo "[*] Compressing module with xz."
			xz -f "linux-stable/$KERNEL_DIRECTORY/$MODULE.ko" >> "$LOG_FILE"
			MODULE_FILE="$MODULE.ko.xz"
		elif [ "$COMPRESS_METHOD" == "gz" ]; then
			echo "[*] Compressing module with gzip."
			gzip "linux-stable/$KERNEL_DIRECTORY/$MODULE.ko" >> "$LOG_FILE"
			MODULE_FILE="$MODULE.ko.gz"
		elif [ "$COMPRESS_METHOD" == "ko" ]; then
			echo "[*] No compression used, continuing without."
			MODULE_FILE="$MODULE.ko"
		else
			echo "[#] ERROR: Unknown compression method used, unable to continue."
			exit
		fi

		echo ""
		echo "[*] Finished making module"
		echo ""
	else
		echo "[#] Error: directory 'linux-stable/$KERNEL_DIRECTORY' does not exist!"
		echo "    Did you download the linux-stable sources to this directory?"
		exit
	fi
}

install_module () {
	echo "[*] Backing up old kernel module as ${TIMESTAMP}_$MODULE_FILE"
	cp -p "/lib/modules/$(uname -r)/kernel/$KERNEL_DIRECTORY/$MODULE_FILE" "${TIMESTAMP}_$MODULE_FILE"
	echo ""
	echo "[*] Installing kernel module."
	echo ""
	echo "    NOTE: This step requires sudo privileges, but can be done manually if you prefer by running:"
	echo "    sudo cp -f \"linux-stable/$KERNEL_DIRECTORY/$MODULE_FILE\" \"/lib/modules/\`uname -r\`/kernel/$KERNEL_DIRECTORY\""
	read -p "    Install now? [Y/n] " INSTALL_DO_CONTINUE

	if [ "${INSTALL_DO_CONTINUE,,}" != "n" ] && [ "${INSTALL_DO_CONTINUE,,}" != "no" ]; then
		sudo cp -f "linux-stable/$KERNEL_DIRECTORY/$MODULE_FILE" "/lib/modules/$(uname -r)/kernel/$KERNEL_DIRECTORY"
		echo "[*] Kernel module installed."
		echo "[*] Inserting kernel module."
		sudo modprobe -r "$MODULE" >> "$LOG_FILE"
		sudo modprobe "$MODULE" >> "$LOG_FILE"
	fi

	echo ""
	echo "[*] Done!"
	echo ""
	echo "    If your Bluetooth dongle is connected you may need to remove it and put it back in for it to work."
	echo "    Happy Bluetoothing!"
	echo ""
}

echo ""
acquire_kernel_sources
prepare_for_compilation
patch_module
make_module

if [ $DO_INSTALL -eq 1 ]; then
	install_module
fi
