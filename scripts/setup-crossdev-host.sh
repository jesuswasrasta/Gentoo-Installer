#!/bin/bash

cd "$dir"

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
