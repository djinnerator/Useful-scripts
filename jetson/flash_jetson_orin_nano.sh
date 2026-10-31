#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# 1. Prompt for NVMe Drive Size and Calculate NUM_SECTORS
# ==============================================================================
read -rp "Enter the size of your NVMe drive in GB or TB (e.g., 2TB, 1TB, 512GB, 256GB, 128GB): " NVME_INPUT
NVME_NORMALIZED=$(echo "$NVME_INPUT" | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')

case "$NVME_NORMALIZED" in
    2TB)
        NUM_SECTORS=3904897024
        ;;
    1TB)
        NUM_SECTORS=1953525168
        ;;
    512GB)
        NUM_SECTORS=975175680
        ;;
    256GB)
        NUM_SECTORS=536870912
        ;;
    128GB)
        NUM_SECTORS=268435456
        ;;
    *)
        PROVIDED_SIZE=$(echo "$NVME_NORMALIZED" | tr -dc '0-9.')
        if [[ -z "$PROVIDED_SIZE" ]]; then
            echo "Error: Invalid NVMe drive size provided."
            exit 1
        fi
        if command -v bc >/dev/null 2>&1; then
            NUM_SECTORS=$(echo "($PROVIDED_SIZE * (1024^3)) / 512" | bc)
        else
            NUM_SECTORS=$(( ${PROVIDED_SIZE%.*} * (1024**3) / 512 ))
        fi
        ;;
esac

echo "Using NUM_SECTORS=${NUM_SECTORS}"

# ==============================================================================
# 2. Prompt for Root Filesystem Encryption (Boolean)
# ==============================================================================
read -rp "Do you want the root filesystem encrypted? (y/n): " ENC_RESPONSE
case "${ENC_RESPONSE,,}" in
    y|yes|true|1)
        ENCRYPT_ROOTFS=true
        ;;
    *)
        ENCRYPT_ROOTFS=false
        ;;
esac

# ==============================================================================
# 3. Prompt for Root Filesystem Size
# ==============================================================================
if [[ "$ENCRYPT_ROOTFS" == true ]]; then
    read -rp "Enter the desired size of the encrypted root filesystem in GiB (e.g., 64): " ROOTFS_SIZE
else
    read -rp "Enter the desired size of the file system in GiB (e.g., 64): " ROOTFS_SIZE
fi
# Strip trailing GiB/GB if included by the user so -S XXXGiB formats cleanly
ROOTFS_SIZE=$(echo "$ROOTFS_SIZE" | sed -E 's/[[:space:]]*[Gg][Ii]?[Bb]?$//')

# ==============================================================================
# 4. Prompt for Security Keys and UEFI Folder Paths
# ==============================================================================
read -e -rp "Enter the path to your PKC.key: " PKC_KEY
read -e -rp "Enter the path to your SBK key: " SBK_KEY
read -e -rp "Enter the path to your ekb.key: " EKB_KEY
read -e -rp "Enter the path to your user encryption key: " USER_ENC_KEY
read -e -rp "Enter the path to your uefi key: " UEFI_KEY
read -e -rp "Enter the path to your uefi folder: " UEFI_DIR

# Convert paths to absolute paths so they remain valid after cd Linux_for_Tegra
PKC_KEY=$(realpath -m "$PKC_KEY")
SBK_KEY=$(realpath -m "$SBK_KEY")
EKB_KEY=$(realpath -m "$EKB_KEY")
USER_ENC_KEY=$(realpath -m "$USER_ENC_KEY")
UEFI_KEY=$(realpath -m "$UEFI_KEY")
UEFI_DIR=$(realpath -m "${UEFI_DIR%/}")

# ==============================================================================
# 5. Prompt for Default User Creation
# ==============================================================================
read -rp "Do you want to create a default user? (y/n): " CREATE_USER_RESPONSE
case "${CREATE_USER_RESPONSE,,}" in
    y|yes|true|1)
        CREATE_DEFAULT_USER=true
        read -rp "Enter username: " DEF_USERNAME
        read -rsp "Enter password: " DEF_PASSWORD
        echo ""
        read -rp "Enter hostname: " DEF_HOSTNAME
        ;;
    *)
        CREATE_DEFAULT_USER=false
        ;;
esac

# ==============================================================================
# 6. Download L4T R39.2.1 Archives
# ==============================================================================
echo "Downloading L4T R39.2.1 archives..."
wget -c "https://developer.nvidia.com/downloads/embedded/L4T/r39_Release_v2.1/release/Jetson_Linux_R39.2.1_aarch64.tbz2" &
PID1=$!
wget -c "https://developer.nvidia.com/downloads/embedded/L4T/r39_Release_v2.1/release/Tegra_Linux_Sample-Root-Filesystem_R39.2.1_aarch64.tbz2" &
PID2=$!
wget -c "https://developer.nvidia.com/downloads/embedded/L4T/r39_Release_v2.1/sources/public_sources.tbz2" &
PID3=$!

# Wait for all downloads to complete before continuing
wait "$PID1" "$PID2" "$PID3"
echo "All downloads completed."

# ==============================================================================
# 7. Extract Archives and Apply Prerequisites/Binaries
# ==============================================================================
tar xf Jetson_Linux_R39.2.1_aarch64.tbz2 && \
sudo tar jxpf Tegra_Linux_Sample-Root-Filesystem_R39.2.1_aarch64.tbz2 -C Linux_for_Tegra/rootfs/ && \
tar xf public_sources.tbz2 && \
tar xf host_overlay_fskp_tools_R39.2.1_aarch64.tbz2 && \
tar xf Linux_for_Tegra/source/nvidia-jetson-optee-source.tbz2 -C Linux_for_Tegra/source && \
cd Linux_for_Tegra && \
sudo ./tools/l4t_flash_prerequisites.sh && \
sudo ./apply_binaries.sh

# ==============================================================================
# 8. Generate Internal QSPI Flash Package
# ==============================================================================
sudo ./l4t_initrd_flash.sh --showlogs --no-flash --network usb0 \
    -u "$PKC_KEY" \
    -v "$SBK_KEY" \
    --uefi-keys "${UEFI_DIR}/uefi_keys.conf" \
    --uefi-enc "$UEFI_KEY" \
    -p "-c bootloader/generic/cfg/flash_t234_qspi.xml" \
    jetson-orin-nano-devkit-super internal

# ==============================================================================
# 9. Create Default User (If Requested)
# ==============================================================================
if [[ "$CREATE_DEFAULT_USER" == true ]]; then
    sudo ./tools/l4t_create_default_user.sh \
        -u "$DEF_USERNAME" \
        -p "$DEF_PASSWORD" \
        -n "$DEF_HOSTNAME" \
        --accept-license
fi

# ==============================================================================
# 10. Copy Signed EKS Image to Internal Flash Directory
# ==============================================================================
sudo cp bootloader/eks_t234_sigheader_encrypt.img.signed tools/kernel_flash/images/internal/

# ==============================================================================
# 11. Generate External NVMe Flash Package (Encrypted vs Unencrypted)
# ==============================================================================
if [[ "$ENCRYPT_ROOTFS" == true ]]; then
    sudo ROOTFS_ENC=1 EXT_NUM_SECTORS="$NUM_SECTORS" ./tools/kernel_flash/l4t_initrd_flash.sh \
        --showlogs \
        -u "$PKC_KEY" \
        -v "$SBK_KEY" \
        --uefi-keys "${UEFI_DIR}/uefi_keys.conf" \
        --uefi-enc "$USER_ENC_KEY" \
        --no-flash \
        --external-device nvme0n1p1 \
        -i "$EKB_KEY" \
        -c ./tools/kernel_flash/flash_l4t_t234_nvme_rootfs_enc.xml \
        -S "${ROOTFS_SIZE}GiB" \
        --external-only \
        --append \
        --network usb0 \
        jetson-orin-nano-devkit-super external
else
    sudo EXT_NUM_SECTORS="$NUM_SECTORS" ./tools/kernel_flash/l4t_initrd_flash.sh \
        --showlogs \
        -u "$PKC_KEY" \
        -v "$SBK_KEY" \
        --uefi-keys "${UEFI_DIR}/uefi_keys.conf" \
        --uefi-enc "$USER_ENC_KEY" \
        --no-flash \
        --external-device nvme0n1p1 \
        -i "$EKB_KEY" \
        -c ./tools/kernel_flash/flash_l4t_t234_nvme_rootfs.xml \
        -S "${ROOTFS_SIZE}GiB" \
        --external-only \
        --append \
        --network usb0 \
        jetson-orin-nano-devkit-super external
fi

# ==============================================================================
# 12. Flash the Target Device
# ==============================================================================
sudo ./tools/kernel_flash/l4t_initrd_flash.sh \
    --showlogs \
    -u "$PKC_KEY" \
    -v "$SBK_KEY" \
    --network usb0 \
    --flash-only \
    jetson-orin-nano-devkit-super