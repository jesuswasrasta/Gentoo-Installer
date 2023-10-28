# WIP!!!
#!/bin/bash

chroot_call 'emerge --newuse --update app-emulation/qemu'
chroot_call '[ -d /proc/sys/fs/binfmt_misc ] || modprobe binfmt_misc'
chroot_call '[ -f /proc/sys/fs/binfmt_misc/register ] || mount binfmt_misc -t binfmt_misc /proc/sys/fs/binfmt_misc'
#chroot_call "echo ':ppc64:M::\x7fELF\x02\x02\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x15:\xff\xff\xff\xff\xff\xff\xff\xfc\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff:/usr/bin/qemu-ppc64:' | tee /proc/sys/fs/binfmt_misc/register"
#chroot_call 'quickpkg app-emulation/qemu'
#chroot_call 'rc-service qemu-binfmt restart'

# Use install script to prepare ps3 env in chroot
path_gentoo_ps3="$path_chroot/root/gentoo-ps3"
try mkdir "$path_gentoo_ps3"
try cp "$dir/gentoo-install.sh" "$path_chroot/root/gentoo-install.sh"
chroot_call "/root/gentoo-install.sh --directory /root/gentoo-ps3 --config qemu-ps3 --branch $branch --sync-portage false $verbose_flag"
#chroot_call "/root/gentoo-install.sh --directory /root/gentoo-ps3 --config ps3 --branch $branch"
#x TODO: ADD new ps3 config, which will chroot_call copy /usr/bin/qemu-ppc64 to gentoo-ps3/usr/bin/
#x In this config disable usage of cpuid2cpuflags!
#x ADD to gentoo-ps3 make.conf
#x root #env FEATURES="-pid-sandbox -network-sandbox" emerge
#x Remove binhost from config 
# TODO: Add flags to ps3-prepare like verbose, branch, etc.
#x TODO: Add FEATURES="buildpkg" to ps3 conf

exit
# Configure and install QEMU
chroot_call 'emerge --newuse --update app-emulation/qemu'
chroot_call '[ -d /proc/sys/fs/binfmt_misc ] || modprobe binfmt_misc'
chroot_call '[ -f /proc/sys/fs/binfmt_misc/register ] || mount binfmt_misc -t binfmt_misc /proc/sys/fs/binfmt_misc'
chroot_call "echo ':ppc64:M::\x7fELF\x02\x02\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x15:\xff\xff\xff\xff\xff\xff\xff\xfc\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff:/usr/bin/qemu-ppc64:' | tee /proc/sys/fs/binfmt_misc/register"
chroot_call 'quickpkg app-emulation/qemu'
chroot_call 'rc-service qemu-binfmt restart'

# Download PPC64 stage3
stage3_download() {
    local path_stage3="$path_tmp/stage3-ppc64.tar.xz"
    echo "$path_stage3"
    local url_autobuilds='https://distfiles.gentoo.org/releases/ppc/autobuilds'
    local stageinfo_url="$url_autobuilds/latest-stage3.txt"
    echo "$stageinfo_url"
    local latest_stage3_content="$(wget -q -O - "$stageinfo_url" --no-http-keep-alive --no-cache --no-cookies)"
        echo " << $latest_stage3_content >> ppc64-$init_system"
    local latest_stage3="$(echo "$latest_stage3_content" | grep "ppc64-$init_system" | head -n 1 | cut -d' ' -f1)"
    echo "$latest_stage3"
    local url_ps3_stage3
    if [ -n "$latest_stage3" ]; then
        url_ps3_stage3="$url_autobuilds/$latest_stage3"
    else
        error "Failed to download Stage3 URL"
    fi
    # Download stage3 file
    try wget "$url_ps3_stage3" -O "$path_stage3" $quiet_flag
    run_extra_scripts ${FUNCNAME[0]}
}

stage3_extract() {
    local path_stage3="$path_tmp/stage3-ppc64.tar.xz"
    try cd "$path_chroot"
    try mkdir "$path_chroot/root/gentoo-ppc64"
    try tar -xvpf "$path_stage3" --xattrs-include="*/*" --numeric-owner -C "$path_chroot/root/gentoo-ppc64"
    try cd "$dir"
    run_extra_scripts ${FUNCNAME[0]}
}

stage3_download
stage3_extract
cd "$path_chroot/root/gentoo-ppc64"
chroot_call 'ROOT=$PWD/ emerge --usepkgonly --oneshot --nodeps qemu'
chroot_call 'echo "EMERGE_DEFAULT_OPTS=\"$EMERGE_DEFAULT_OPTS --exclude app-emulation/qemu\"" | tee -a /root/gentoo-ppc64/etc/portage/make.conf'
chroot_call 'echo app-emulation/qemu | tee -a /root/gentoo-ppc64/var/lib/portage/world'
chroot_call 'echo "FEATURES=\"${FEATURES} -pid-sandbox -network-sandbox\"" | tee -a /root/gentoo-ppc64/etc/portage/make.conf'
try mkdir -p "$path_chroot/root/gentoo-ppc64/var/db/repos/gentoo"

# Setup ppc64 environment

# Run chroot



# # These settings were set by the catalyst build script that automatically
# # built this stage.
# # Please consult /usr/share/portage/config/make.conf.example for a more
# # detailed example.

# COMMON_FLAGS="-O2 -pipe -mcpu=cell -mtune=cell -mabi=altivec -maltivec"
# CFLAGS="${COMMON_FLAGS}"
# CXXFLAGS="${COMMON_FLAGS}"
# FCFLAGS="${COMMON_FLAGS}"
# FFLAGS="${COMMON_FLAGS}"
# # WARNING: Changing your CHOST is not something that should be done lightly.
# # Please consult https://wiki.gentoo.org/wiki/Changing_the_CHOST_variable before changing.
# CHOST="powerpc64-unknown-linux-gnu"

# # NOTE: This stage was built with the bindist Use flag enabled

# # This sets the language of build output to English.
# # Please keep this setting intact when reporting bugs.
# LC_MESSAGES=C
# EMERGE_DEFAULT_OPTS="$EMERGE_DEFAULT_OPTS --exclude app-emulation/qemu"

# MAKEOPTS="-j6 -l2"
# FEATURES="buildpkg -pid-sandbox"
# ACCEPT_LICENSE="*"
# VIDEO_CARDS=""
# USE="ps3 zeroconf mdnsresponder-compat"
# BINPKG_FORMAT="gpkg"
# #BINPKG_COMPRESS="lz4"
# FEATURES="${FEATURES} -pid-sandbox -network-sandbox"
