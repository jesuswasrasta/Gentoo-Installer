#!/bin/bash

# Configure host crossdev environment and add targets.

chroot_call 'mkdir -p /var/db/repos/crossdev/{profiles,metadata}'
chroot_call 'chown -R portage:portage /var/db/repos/crossdev'
chroot_call 'mkdir -p /etc/portage/repos.conf'

echo 'crossdev' >> "$path_chroot/var/db/repos/crossdev/profiles/repo_name"
echo 'masters = gentoo' >> "$path_chroot/var/db/repos/crossdev/metadata/layout.conf"
echo '[crossdev]' >> "$path_chroot/etc/portage/repos.conf/crossdev.conf"
echo 'location = /var/db/repos/crossdev' >> "$path_chroot/etc/portage/repos.conf/crossdev.conf"
echo 'priority = 10' >> "$path_chroot/etc/portage/repos.conf/crossdev.conf"
echo 'masters = gentoo' >> "$path_chroot/etc/portage/repos.conf/crossdev.conf"
echo 'auto-sync = no' >> "$path_chroot/etc/portage/repos.conf/crossdev.conf"

# Default configuration for the PS3 - Should be added to config of target and not stored directly here.
chroot_call 'crossdev --b '~2.40' --g '~13.2.1_p20230826' --k '~6.5' --l '~2.37' -t powerpc64-unknown-linux-gnu --abis altivec'

# TODO: Get value of profile somehow and powerpc64-unknown-linux-gnu.
chroot_call 'PORTAGE_CONFIGROOT=/usr/powerpc64-unknown-linux-gnu eselect profile set 1'

# TODO: Maybe add default portage configuration, make.conf here.