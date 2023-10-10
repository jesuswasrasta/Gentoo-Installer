#!/bin/bash

# This script automates the setup and configuration of Gentoo Linux for the PlayStation 3 (PS3).
# It includes disk partitioning, filesystem creation, package installation, and system configuration.
# Customize the variables in the CONFIGURATION section to tailor the installation to your needs.
# Note: A configured OtherOS or OtherOS++ environment, Petitboot, and a running Linux environment on the PS3 are required for executing this script.
# You can use Live Gentoo USB to utilize the installation script.
# Warning: Running this script will result in the erasure of all data on the specified disk.

# Read variables.

declare disk_device # [/dev/ps3dd / /dev/ps3da / dev/sda] For OtherOS++ use ps3dd, for OtherOS ps3da. To install on USB drive, use sda.
declare config # TODO: Store config in seperate files, and load over HTTP.

# ###############################################################################################
# CONFIGURATION =================================================================================
# ###############################################################################################

arch='ppc64' # For the PS3 always use ppc64.
init_system='openrc' # [openrc/systemd]. Currently works only with openrc.
profile="default/linux/$arch/17.0" # Customize is you want the GUI.
base_url='https://distfiles.gentoo.org/releases/ppc/autobuilds'

disk_scheme='gpt' # [gpt/dos]. Suggest using gpt.

hostname='PS3'
root_password='' # Empty string means remove password.
locale='en_US.utf8' # Default locale. Please include also in locales.

ssh_allow_root=true # Enable root login through SSH.
ssh_allow_passwordless=true # Enable logging in without password if user doesn't have one.

kernel_version='6.5.4'

## Partitions -----------------------------------------------------------------------------------

declare -a disk_partitions=( # index:mount_order:file_system:mount_point:size:options:dump:pass.
    1:1:ext3:/boot:+256MiB:defaults,noatime:1:2 # BOOT. Don`t use ext4 for boot, petitboot won`t detect it
    2:0:btrfs:/:-4100MiB:defaults,noauto:0:1 # ROOT
    3:2:swap:none:+4GiB:sw:0:0 # SWAP
)

## Locales --------------------------------------------------------------------------------------

declare -a locales=(
    'en_US ISO-8859-1'
    'en_US.UTF-8 UTF-8'
)

## Make conf ------------------------------------------------------------------------------------

declare -A make_conf=(
    [COMMON_FLAGS]='-O2 -pipe -mcpu=cell -mtune=cell -mabi=altivec -maltivec'
    [USE]='ps3 zeroconf mdnsresponder-compat'
    [MAKEOPTS]='-j6 -l2' # If not using distcc, use -j3.
    [ACCEPT_LICENSE]='*' # Automatically accept all licenses.
    [FEATURES]='distcc'
)

## Packages and tools ---------------------------------------------------------------------------

declare -A package_use=(
    [00cpu-flags]='*/* CPU_FLAGS_PPC: altivec'
)

declare -A package_accept_keywords=(
    [app-misc_ps3pf_utils]='app-misc/ps3pf_utils ~ppc64'
)

declare -a guest_tools=(
    app-admin/sysklogd
    app-portage/gentoolkit
    net-misc/ntp
    app-misc/ps3pf_utils
    sys-devel/distcc
    net-dns/avahi
)

declare -A guest_rc_startup=(
    [boot]='net.eth0'
    [default]='sysklogd sshd ntpd ntp-client avahi-daemon'
)

# ###############################################################################################
# Helper functions ==============================================================================
# ###############################################################################################

quiet_flag='--quiet'
quiet_flag_short='-q'

quiet() {
    if [ -n "$quiet_flag" ]
    then
        "$@" > /dev/null
    else
        "$@"
    fi
}

welcome() {
    printf "\033[1;36m[ $title started ]\033[0m\n"
}

message() {
    printf "\033[0;33m> $@\033[0m\n"
}

summary() {
    printf "\033[1;4;32m[ $title done ]\033[0m\n"
}

error() {
    printf "\033[1;31m$@\033[0m\n"
    exit
}

try() {
    "$@"
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        error "[ $title failed ]"
        exit $exit_code
    fi
}

print_usage() {
    message "Usage: $0 --device <device> --config <config> [-v]"
}

# ###############################################################################################
# FUNCTIONS =====================================================================================
# ###############################################################################################

### Helper variables
title='BOOTSTRAP GENTOO LINUX FOR THE PS3'
declare -a disk_partitions_sorted_by_mount_order # Will be filled by the script itself.
declare url_gentoo_stage3 # Will be fetched for the newest available stage3.
dir="$(pwd)" # Current directory where script was called from.
path_chroot="$(pwd)/gentoo/chroot"
path_tmp="$(pwd)/gentoo/tmp"

## Disk preparation -----------------------------------------------------------------------------

stage000_read_variables() {
    while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--device)
            shift
            if [[ $# -gt 0 ]]; then
                disk_device="$1"
            fi
            ;;
        -c|--config)
            shift
            if [[ $# -gt 0 ]]; then
                config="$1"
            fi
            ;;
        -v|--verbose)
            unset quiet_flag
            unset quiet_flag_short
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
    shift
    done
}

stage000_validate_input_data() {
    if [ -z "$disk_device" ]; then
        print_usage
        exit 1
    fi
    if [ -z "$config" ]; then
        print_usage
        exit 1
    fi
}

stage000_download_config() {
    echo "Download config"
}

stage000_sort_partitions_by_mount_order() {
    IFS=$'\n' read -r -d '' -a disk_partitions_sorted_by_mount_order < <(
        for partition in "${disk_partitions[@]}"; do
            echo "$partition"
        done | tr ':' $'\t' | sort -k2,2n | tr $'\t' ':'
    )
}

stage001_validate_disk() {
    # Check if disk can be used for the installation.
    # Validate if it's not currently mounted, and if device exists.
    if [ ! -e "$disk_device" ]; then
        error "Device $disk_device does not exists."
    fi
    if lsblk -no MOUNTPOINT "$disk_device" | grep -q -v "^$"; then
        error "Device $disk_device is currently in use. Unmount it before usage."
    fi
}

stage002_clean_signatures() {
    # Cleans signatures from partition table and every partition.
    for partition in "$disk_device"*; do
        if [[ -b "$partition" && "$partition" != "$disk_device" ]]; then
                try quiet wipefs -fa "$partition"
        fi
    done
    try quiet wipefs -fa "$disk_device"
    try sleep 1 # Without sleep blockdev below sometimes fails
    try quiet blockdev --rereadpt -v "$disk_device"
}

stage003_create_partitions() {
    # Create partitions on device.
    local fdisk_command=''

    if [ "$disk_scheme" = 'gpt' ]; then
        fdisk_command='g\n'
    fi
    if [ "$disk_scheme" = 'dos' ]; then
        fdisk_command='o\n'
    fi

    # Creating partition for given configuration.
    create_partition_from_config() {
        local disk_device="$1"
        local disk_scheme="$2"
        local partition_data="$3"
        local partition_data_fragments=(${partition_data//:/ })
        local partition_data_index="${partition_data_fragments[0]}"
        local partition_data_size="${partition_data_fragments[4]}"
        local primary_partition_selector="" # Adds "p\n" for MBR partition scheme to command.
        if [ "$disk_scheme" = 'dos' ]; then
            primary_partition_selector='p\n'
        fi
        fdisk_command="${fdisk_command}n\n${primary_partition_selector}${partition_data_index}\n\n${partition_data_size}\n"
    }

    for part_config in "${disk_partitions[@]}"; do
        create_partition_from_config "$disk_device" "$disk_scheme" "$part_config"
    done
    # Write new partition scheme
    fdisk_command="${fdisk_command}w\n"
    printf "$fdisk_command" | try quiet fdisk "$disk_device" --wipe auto
}

stage004_create_filesystems() {
    # Creating filesystem for given configuration.
    create_filesystem_from_config() {
        local disk_device="$1"
        local partition_data="$2"
        local partition_data_fragments=(${partition_data//:/ })
        local partition_data_index="${partition_data_fragments[0]}"
        local partition_data_filesystem="${partition_data_fragments[2]}"
        local partition_device="${disk_device}${partition_data_index}"
        case "$partition_data_filesystem" in
            'vfat' ) try quiet mkfs.vfat -F32 "$partition_device";;
            'ext3' ) try quiet mkfs.ext3 -F $quiet_flag_short "$partition_device";;
            'ext4' ) try quiet mkfs.ext4 -F $quiet_flag_short "$partition_device";;
            'btrfs') try quiet mkfs.btrfs -f $quiet_flag_short "$partition_device";;
            'swap' ) try quiet mkswap $quiet_flag_short "$partition_device";;
            *      ) error "Unknown partition filesystem $partition_data_filesystem"
        esac
    }
    for part_config in "${disk_partitions[@]}"; do
        create_filesystem_from_config "$disk_device" "$part_config"
    done
}

stage005_mount_partitions() {
    if [ ! -d "$path_chroot" ]; then
        try mkdir -p "$path_chroot"
    fi

    mount_filesystem_from_config() {
        local disk_device="$1"
        local partition_data="$2"
        local partition_data_fragments=(${partition_data//:/ })
        local partition_data_index="${partition_data_fragments[0]}"
        local partition_data_filesystem="${partition_data_fragments[2]}"
        local partition_data_mount_point="${partition_data_fragments[3]}"
        local partition_device="${disk_device}${partition_data_index}"
        local partition_mount_path="$path_chroot$partition_data_mount_point"
        if [ "$partition_data_mount_point" != 'none' ]; then
            if [ ! -d "$partition_mount_path" ]; then
                try quiet mkdir "$partition_mount_path"
            fi
            try quiet mount "$partition_device" "$partition_mount_path"
        fi
        if [ "$partition_data_filesystem" = 'swap' ]; then
            try quiet swapon "$partition_device"
        fi
    }
    for part_config in "${disk_partitions_sorted_by_mount_order[@]}"; do
        mount_filesystem_from_config "$disk_device" "$part_config"
    done
}

# ###############################################################################################
# Downloading files =============================================================================
# ###############################################################################################

stage100_get_stage3_url() {
    local stageinfo_url="$base_url/latest-stage3.txt"
    local latest_stage3_content="$(wget -q -O - "$stageinfo_url")"
    local latest_ppc64_stage3="$(echo "$latest_stage3_content" | grep "$arch-$init_system" | head -n 1 | cut -d' ' -f1)"
    if [ -n "$latest_ppc64_stage3" ]; then
        url_gentoo_stage3="$base_url/$latest_ppc64_stage3"
    else
        error "Failed to get Stage3 URL"
    fi
}

stage101_download_stage3() {
    # Download stage3 file
    try quiet wget "$url_gentoo_stage3" -O "$path_chroot/stage3.tar.xz" $quiet_flag
}

stage102_extract_stage3() {
    try cd "$path_chroot"
    try quiet tar -xvpf 'stage3.tar.xz'
    try rm 'stage3.tar.xz'
    try cd "$dir"
}

# ###############################################################################################
# Configuring system ============================================================================
# ###############################################################################################

stage200_mount_devices() {
    try cd "$path_chroot"
    try mount --types proc /proc proc
    try mount --rbind /sys sys
    try mount --make-rslave sys
    try mount --rbind /dev dev
    try mount --make-rslave dev
    try mount --bind /run run
    try mount --make-slave run
    try cd "$dir"
}

stage201_copy_resolv_conf() {
    try cp --dereference '/etc/resolv.conf' "$path_chroot/etc/resolv.conf"
}

stage202_setup_make_conf() {
    local path_make_conf="$path_chroot/etc/portage/make.conf"
    insert_config() {
        local key="$1"
        local value="$2"
        if grep -q "$key=" "$path_make_conf"; then
            try sed -i "s/^$key=.*/$key=\"$value\"/" "$path_make_conf"
        else
            echo "$key=\"$value\"" | try tee -a "$path_make_conf" > /dev/null
        fi
    }
    for key in "${!make_conf[@]}"; do
        insert_config "$key" "${make_conf[$key]}"
    done
}

stage203_setup_packages_use() {
    local path_package_use="$path_chroot/etc/portage/package.use"
    for key in "${!_package_use[@]}"; do
        echo "${package_use[$key]}" | try tee -a "$path_package_use/$key" > /dev/null
    done
}

stage204_setup_package_accept_keywords() {
    local path_package_accept_keywords="$path_chroot/etc/portage/package.accept_keywords"
    for key in "${!package_accept_keywords[@]}"; do
        echo "${package_accept_keywords[$key]}" | try tee -a "$path_package_accept_keywords/$key" > /dev/null
    done
}

stage205_setup_locale() {
    local path_make_conf="$path_chroot/etc/locale.gen"
    for ((i=0; i < "${#locales[@]}"; i++)); do
        echo "${locales[$i]}" | try tee -a "$path_make_conf" > /dev/null
    done
}

stage206_setup_fstab() {
    local path_fstab="$path_chroot/etc/fstab"
    add_partition_entry() {
        local disk_device="$1"
        local partition_data="$2"
        local partition_data_fragments=(${partition_data//:/ })
        local partition_data_index="${partition_data_fragments[0]}"
        local partition_data_filesystem="${partition_data_fragments[2]}"
        local partition_data_mount_point="${partition_data_fragments[3]}"
        local partition_data_flags="${partition_data_fragments[5]}"
        local partition_data_dump="${partition_data_fragments[6]}"
        local partition_data_pass="${partition_data_fragments[7]}"
        local partition_device="${disk_device}${partition_data_index}"
        local partition_mount_path="$path_chroot$partition_data_mount_point"
        local entry="${partition_device} ${partition_data_mount_point} ${partition_data_filesystem} ${partition_data_flags} ${partition_data_dump} ${partition_data_pass}"
        echo "$entry" | try tee -a "$path_fstab" > /dev/null
    }
    for part_config in "${disk_partitions_sorted_by_mount_order[@]}"; do
        add_partition_entry "$disk_device" "$part_config"
    done
}

stage207_setup_hostname() {
    local path_hostname="$path_chroot/etc/hostname"
    echo "$hostname" | try tee "$path_hostname" > /dev/null
}

stage208_install_kernel() {
    local linux_filename="linux-$kernel_version.tar.xz"
    local url_linux_download="https://github.com/damiandudycz/ps3/raw/main/$linux_filename"
    local path_linux_download="$path_tmp/$linux_filename"
    local path_linux_extract="$path_tmp/linux-$kernel_version"

    local path_chroot_boot="$path_chroot/boot"
    local path_kernel_vmlinux="$path_linux_extract/vmlinux"
    local path_kernel_initramfs="$path_linux_extract/initramfs.img"
    local path_kernel_modules="$path_linux_extract/modules/$kernel_version-gentoo-ppc64"
    local path_chroot_modules="$path_chroot/lib/modules/$kernel_version-gentoo-ppc64"

    if [ ! -d "$path_tmp" ]; then
        try mkdir -p "$path_tmp"
    fi
    if [ ! -d "$path_linux_extract" ]; then
        try mkdir -p "$path_linux_extract"
    fi

    try quiet wget "$url_linux_download" -O "$path_linux_download" $quiet_flag
    try quiet tar -xvpf "$path_linux_download" --directory "$path_linux_extract"

    if [ ! -d "$path_chroot_modules" ]; then
        try mkdir -p "$path_chroot_modules"
    fi

    try cp "$path_kernel_vmlinux" "$path_chroot_boot/vmlinux-$kernel_version"
    try cp "$path_kernel_initramfs" "$path_chroot_boot/initramfs-$kernel_version.img"
    try cp -r "$path_kernel_modules"/* "$path_chroot_modules"

    try rm -rf "$path_linux_download" "$path_linux_extract"
}

stage209_setup_kboot_entry() {
    local disk_device_name=$(echo "$disk_device" | rev | cut -d'/' -f1 | rev)

    local root_index=0
    local boot_index=0

    # Find root and boot partition indexes
    scan_partition_config() {
        local disk_device="$1"
        local partition_data="$2"
        local partition_data_fragments=(${partition_data//:/ })
        local partition_data_index=${partition_data_fragments[0]}
        local partition_data_mount_point=${partition_data_fragments[3]}
        if [ "$partition_data_mount_point" = '/' ]; then
            root_index=$partition_data_index
        fi
        if [ "$partition_data_mount_point" = '/boot' ]; then
            boot_index=$partition_data_index
        fi
    }
    for part_config in "${disk_partitions[@]}"; do
        scan_partition_config "$disk_device" "$part_config"
    done
    if [ $boot_index -eq 0 ]; then
        boot_index=$root_index
    fi

    local kboot_entry1="$hostname='${disk_device_name}${boot_index}:/vmlinux-$kernel_version initrd=${disk_device_name}${boot_index}:/initramfs-$kernel_version.img root=/dev/${disk_device_name}${root_index} video=ps3fb:mode:133 rhgb'"
    echo "$kboot_entry1" | try tee "$path_chroot/boot/kboot.conf" > /dev/null
}

stage210_setup_ssh() {
    local sshd_path="$path_chroot/etc/ssh/sshd_config"
    if [ $ssh_allow_root = true ]; then
        try sed -i 's/^#PermitRootLogin .*/PermitRootLogin yes/' "$sshd_path"
    fi
    if [ $ssh_allow_passwordless = true ]; then
        try sed -i 's/^#PermitEmptyPasswords .*/PermitEmptyPasswords yes/' "$sshd_path"
    fi
}

stage211_setup_network() {
    local path_initd="$path_chroot/etc/init.d"
    ln -s 'net.lo' "$path_initd/net.eth0"
}

# ###############################################################################################
# Actions inside chroot =========================================================================
# ###############################################################################################

stage300_env_update() {
    try quiet chroot "$path_chroot" '/bin/bash' -c 'env-update && source /etc/profile'
}

stage301_set_password() {
    try quiet chroot "$path_chroot" '/bin/bash' -c "usermod --password '$root_password' root"
}

stage302_generate_locales() {
    try quiet chroot "$path_chroot" '/bin/bash' -c 'locale-gen'
    try quiet chroot "$path_chroot" '/bin/bash' -c "eselect locale set $locale"
    try quiet chroot "$path_chroot" '/bin/bash' -c 'env-update && source /etc/profile'
}

stage303_fetch_portage_repository() {
    try quiet chroot "$path_chroot" '/bin/bash' -c 'emerge-webrsync && emerge --sync'
}

stage304_select_profile() {
    try quiet chroot "$path_chroot" '/bin/bash' -c "eselect profile set $profile"
    try quiet chroot "$path_chroot" '/bin/bash' -c 'env-update && source /etc/profile'
}

stage305_update_system() {
    try quiet chroot "$path_chroot" '/bin/bash' -c "emerge --newuse --deep --update @system @world $quiet_flag"
}

stage306_install_tools() {
    for package in "${guest_tools[@]}"; do
        try quiet chroot "$path_chroot" '/bin/bash' -c "emerge $package $quiet_flag"
    done
}

stage307_revdep_rebuild() {
    try quiet chroot "$path_chroot" '/bin/bash' -c "revdep-rebuild $quiet_flag"
}

stage308_setup_rc_autostart() {
    for key in "${!guest_rc_startup[@]}"; do
        for tool in ${guest_rc_startup[$key]}; do
            try quiet chroot "$path_chroot" '/bin/bash' -c "rc-update add $tool $key"
        done
    done
}

# ###############################################################################################
# Cleaning ======================================================================================
# ###############################################################################################

stage900_cleanup_news() {
    try quiet chroot "$path_chroot" '/bin/bash' -c 'eselect news read all'
}

stage901_cleanup_portage() {
    try quiet chroot "$path_chroot" '/bin/bash' -c 'emerge --depclean'
    try quiet chroot "$path_chroot" '/bin/bash' -c 'eclean --deep distfiles'
    try quiet chroot "$path_chroot" '/bin/bash' -c 'eclean --deep packages'
    try rm -rf "$path_chroot/var/cache/distfiles"/*
}

stage902_unmount_devices() {
    umount -l "$path_chroot/dev"{"/shm","/pts"}
    # TODO: Umount other devices, like proc, run, etc
}

stage903_unmount_partitions() {
    unmount_filesystem_from_config() {
        local disk_device="$1"
        local partition_data="$2"
        local partition_data_fragments=(${partition_data//:/ })
        local partition_data_index=${partition_data_fragments[0]}
        local partition_data_filesystem=${partition_data_fragments[2]}
        local partition_data_mount_point=${partition_data_fragments[3]}
        local partition_device=${disk_device}${partition_data_index}
        if [ "$partition_data_filesystem" = 'swap' ]; then
            echo swapoff $partition_device
            try quiet swapoff $partition_device
        fi
#        if [ "$partition_data_mount_point" != 'none' ]; then
#            echo umount $partition_device
#        fi
    }
    umount -R $path_chroot

    # Reverse order of mounting
    for ((i=${#_disk_partitions_sorted_by_mount_order[@]} - 1; i >= 0 ; i--)); do
        local part_config="${disk_partitions_sorted_by_mount_order[$i]}"
        unmount_filesystem_from_config $disk_device $part_config
    done
}

# ###############################################################################################
# MAIN PROGRAM ==================================================================================
# ###############################################################################################

stage000_read_variables "$@"
stage000_validate_input_data
stage001_validate_disk

welcome

stage000_download_config
## Setup disk -----------------------------------------------------------------------------------
stage000_sort_partitions_by_mount_order
stage002_clean_signatures
stage003_create_partitions
stage004_create_filesystems
stage005_mount_partitions

## Download and extract stage3 ------------------------------------------------------------------
stage100_get_stage3_url
stage101_download_stage3
stage102_extract_stage3

## Setup PS3 Gentoo Linux -----------------------------------------------------------------------
stage200_mount_devices
stage201_copy_resolv_conf
stage202_setup_make_conf
stage203_setup_packages_use
stage204_setup_package_accept_keywords
stage205_setup_locale
stage206_setup_fstab
stage207_setup_hostname
stage208_install_kernel
stage209_setup_kboot_entry
stage210_setup_ssh
stage211_setup_network

## Setup PS3 Gentoo internal chroot environment -------------------------------------------------
stage300_env_update
stage301_set_password
stage302_generate_locales
stage303_fetch_portage_repository
stage304_select_profile
stage305_update_system
stage306_install_tools
stage307_revdep_rebuild
stage308_setup_rc_autostart

## Cleanup and exit -----------------------------------------------------------------------------
stage900_cleanup_news
stage901_cleanup_portage
stage902_unmount_devices
stage903_unmount_partitions

## Summary --------------------------------------------------------------------------------------
summary

# ###############################################################################################

# TODO: Delete resolv.conf in cleanup
# TODO: Distcc configuration
