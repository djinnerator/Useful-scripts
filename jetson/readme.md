# Jetson Orin Nano Devkit Super — Secure NVMe Flashing Script (L4T R39.2.1)

An interactive Bash automation script (`flash_jetson_orin_nano.sh`) designed to download, configure, sign, and flash **NVIDIA Jetson Linux (L4T R39.2.1)** onto an **NVIDIA Jetson Orin Nano Developer Kit (Super configuration)** using an external NVMe SSD (`nvme0n1p1`).

This script streamlines the end-to-end workflow for **Secure Boot (PKC + SBK)**, **UEFI Secure Boot & Payload Encryption**, **OP-TEE EKS integration**, and optional **LUKS Disk / Root Filesystem Encryption**.

## Features

* **Automated Sector Calculation:** Supports standard NVMe capacities (`128GB`, `256GB`, `512GB`, `1TB`, `2TB`) with automatic fallback calculation for custom drive sizes.

* **Configurable RootFS Encryption:** Choose interactively between an encrypted (`ROOTFS_ENC=1`) or unencrypted external NVMe root filesystem, along with custom partition sizing.

* **Full Hardware & UEFI Security Integration:** Supports Public Key Cryptography (`PKC`), Secure Boot Key (`SBK`), Encrypted Keyblob (`EKB`), User Encryption keys, and UEFI signing/encryption keys.

* **Headless Default User Creation:** Optionally pre-configures the default OEM user account, password, and hostname prior to flashing.

* **Parallel Archive Downloads:** Automatically fetches the official L4T R39.2.1 BSP, Sample Root Filesystem, and Public Sources simultaneously with resume support (`wget -c`).

* **Two-Stage Initrd Packaging & Flashing:** Generates the signed internal QSPI bootloader images and external NVMe filesystem images before executing the final flash over `usb0`.

## Prerequisites

### 1. Hardware Requirements

* **Target Device:** NVIDIA Jetson Orin Nano Developer Kit (`jetson-orin-nano-devkit-super`) with an M.2 NVMe SSD installed.

* **Host Machine:** x86_64 Ubuntu Linux host PC with at least **60 GB of free disk space** and `sudo` privileges.

* **Connection:** USB Type-C data cable connecting the host PC to the Jetson Orin Nano, with the Jetson placed into **Force Recovery Mode**.

### 2. Host Packages

Ensure basic utilities required by the script are installed before starting:

```
sudo apt-get update && sudo apt-get install -y wget bc coreutils tar bzip2

```

*(Note: L4T-specific flashing dependencies are automatically installed during execution via `l4t_flash_prerequisites.sh`.)*

### 3. Required Local Files & Security Keys

Before running the script, make sure you have the following files prepared:

1. **FSKP Host Overlay Archive:**
   Place `host_overlay_fskp_tools_R39.2.1_aarch64.tbz2` in the **same directory** where you run the script (this archive is extracted in Step 7 alongside the downloaded L4T packages).

2. **Cryptographic Keys & UEFI Configuration:**
   Have the paths ready for your generated security keys (supports Tab-completion during script prompts):

| Prompt | Description | 
| ----- | ----- | 
| **PKC Key (`PKC.key`)** | RSA/ECDSA private key used for Bootloader Secure Boot signing. | 
| **SBK Key** | Secure Boot Key file used for bootloader encryption. | 
| **EKB Key (`ekb.key`)** | Disk encryption key corresponding to your Encrypted Keyblob (EKS). | 
| **User Encryption Key** | Key used for external NVMe image / UEFI payload encryption during external packaging. | 
| **UEFI Key** | Key passed to `--uefi-enc` during internal QSPI packaging. | 
| **UEFI Folder** | Path to the directory containing your `uefi_keys.conf` file and associated UEFI certificates/keys. | 

> **Important Note on EKS Image:** Step 10 copies `bootloader/eks_t234_sigheader_encrypt.img.signed` to `tools/kernel_flash/images/internal/`. Ensure your workflow or overlay generates/provides the signed EKS image inside the `bootloader/` directory during or prior to the internal QSPI packaging phase.

## Usage

### 1. Clone the Repository & Make Executable

```
chmod +x flash_jetson_orin_nano.sh

```

### 2. Put the Jetson into Force Recovery Mode

1. Power off the Jetson Orin Nano completely.

2. Place a jumper across the **Force Recovery (`FC REC`)** and **Ground (`GND`)** pins on the button header underneath the module.

3. Connect the USB-C port on the Jetson to your Ubuntu host PC.

4. Connect the power supply to turn on the board.

5. Verify the device is detected on your host:

   ```
   lsusb | grep -i nvidia
   
   ```

### 3. Run the Script

```
./flash_jetson_orin_nano.sh

```

## Interactive Prompts Guide

When executed, the script will walk you through the following configuration prompts before beginning any downloads or builds:

1. **NVMe Drive Size:**

   * Enter `2TB`, `1TB`, `512GB`, `256GB`, or `128GB` to use predefined sector counts, or enter a custom numeric size in GiB (calculated as $\text{NUM\_SECTORS} = \frac{\text{Size} \times 1024^3}{512}$).

2. **Root Filesystem Encryption:**

   * Enter `y` to enable LUKS rootfs encryption (`ROOTFS_ENC=1`) or `n` for a standard unencrypted ext4 rootfs.

3. **Root Filesystem Size:**

   * Specify the desired size of the root partition in GiB (e.g., `64` for `64GiB`).

4. **Security Key Paths:**

   * Provide the file paths to your `PKC.key`, `SBK` key, `ekb.key`, `user encryption key`, `uefi key`, and `uefi folder`. Relative paths and `~` are automatically resolved to absolute paths.

5. **Default User Creation:**

   * Enter `y` to bypass the first-boot OEM configuration wizard by providing a default `username`, `password`, and `hostname`.

## Script Execution Pipeline

Once all prompts are completed, the script executes the following automated pipeline:

1. **Download L4T R39.2.1 Packages:** Downloads the L4T Driver Package (BSP), Sample Root Filesystem, and Public Sources in parallel.

2. **Extract & Prepare Environment:** Extracts the BSP, populates `Linux_for_Tegra/rootfs/`, unpacks OP-TEE sources and FSKP overlay tools, installs host prerequisites (`l4t_flash_prerequisites.sh`), and applies NVIDIA binaries (`apply_binaries.sh`).

3. **Generate Internal QSPI Package:** Runs `l4t_initrd_flash.sh --no-flash` for the internal QSPI storage using `flash_t234_qspi.xml` with PKC, SBK, and UEFI keys.

4. **Configure OEM Default User:** Runs `l4t_create_default_user.sh` (if enabled).

5. **Stage Signed EKS Image:** Copies `bootloader/eks_t234_sigheader_encrypt.img.signed` into `tools/kernel_flash/images/internal/`.

6. **Generate External NVMe Package:** Runs `l4t_initrd_flash.sh --no-flash --external-only --append` for `nvme0n1p1` using either `flash_l4t_t234_nvme_rootfs_enc.xml` (encrypted) or `flash_l4t_t234_nvme_rootfs.xml` (unencrypted).

7. **Flash Target Device:** Executes `l4t_initrd_flash.sh --flash-only` over `--network usb0` to write both internal QSPI and external NVMe images to the board.

## Troubleshooting

* **Permission Denied / Sudo Prompts:** The script invokes `sudo` during archive extraction and flashing. Keep an eye on the terminal in case your `sudo` credentials time out during large downloads.

* **USB Network Timeout (`usb0`) during Flashing:** Ensure USB autosuspend is disabled on your host machine and avoid using USB hubs or charge-only USB-C cables.

* **RootFS Size Exceeds NVMe Capacity:** When enabling RootFS encryption (`ROOTFS_ENC=1`), ensure the requested `ROOTFS_SIZE` leaves sufficient space on the NVMe drive for boot, recovery, and reserved partitions.
