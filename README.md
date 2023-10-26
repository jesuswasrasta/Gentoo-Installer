# Gentoo-Installer
Automatic installer and configurator of Gentoo linux for various platforms.

To install on the PS3, boot into any recent linux distribution, setup the date and networking and:

To install on the whole drive:
`./gentoo-install.sh --device /dev/ps3dd --config ps3 --verbose`
this will format the given harddrive!

To install into selected directory without formatting the drive:
`./gentoo-install.sh --directory /mnt/gentoo --config ps3 --verbose`
and after installer finished, add fstab configuration and kboot entry.

If you want to customize configuration, you can download file config/ps3, edit it and use as
`./gentoo-install.sh --device /dev/ps3dd --custom-config ps3_file_path --verbose`

To use distcc during installation, use --distcc flag:
`./gentoo-install.sh --device /dev/ps3dd --config ps3 --distcc "192.168.0.50,cpp,lzo"`
this will format the given harddrive!
