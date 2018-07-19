#!/usr/bin/env bash

# Based on https://github.com/netson/ubuntu-unattended

# file names & paths
tmp="/tmp/createiso"  # working area
target='/vagrant' # destination of ISOs
currentuser="$(whoami)"
PRESEED_SERVER="${PRESEED_SERVER:-nyx.ucsd.edu}"

# fail if run as root
if [ "$currentuser" == "root" ]; then
  echo " Please run as a normal user"
  exit 1
fi

[[ -d "$tmp" ]] && { echo "$tmp exists. Please remove and re-run."; exit 1; }
mkdir -p "$tmp" || exit 1

cleanup() {
  sudo umount --lazy "$tmp/iso_new"
  sudo umount "$tmp/iso_org"
  sudo rm -rf "$tmp"
}

trap cleanup EXIT

# get the latest version of Ubuntu LTS

tmphtml=$tmp/tmphtml
rm -f "$tmphtml" >/dev/null 2>&1
curl --remote-time --silent --output "$tmphtml" 'http://releases.ubuntu.com/'

bion=$(grep -F Bionic "$tmphtml" | head -1 | awk '{print $3}')

download_file="ubuntu-$bion-server-amd64.iso"
download_location="http://cdimage.ubuntu.com/releases/$bion/release"
new_iso_name="ubuntu-$bion-server-amd64-unattended.iso"

# download the ubunto iso. If it already exists, do not delete in the end.
cd "$tmp" || exit 1
if [[ ! -f $target/$download_file ]]; then
  echo "-> Downloading $download_file: "
  curl \
    --remote-time \
    --output "$target/$download_file" "$download_location/$download_file" \
    --output "$target/SHA256SUMS"     "$download_location/SHA256SUMS"     \
    --output "$target/SHA256SUMS.gpg" "$download_location/SHA256SUMS.gpg"
fi
if [[ ! -f "$target/$download_file" ]]; then
  echo "Error: Failed to download ISO: $download_location/$download_file"
  echo "This file may have moved or may no longer exist."
  echo
  echo "You can download it manually and move it to $target/$download_file"
  echo "Then run this script again."
  exit 1
fi

# verify iso
echo "-> Verifying Signatures"
gpg \
  --quiet \
  --no-default-keyring \
  --keyring /etc/apt/trusted.gpg.d/ubuntu-keyring-2012-cdimage.gpg \
  --keyring /usr/share/keyrings/ubuntu-archive-removed-keys.gpg \
  --verify \
  "$target/SHA256SUMS.gpg" "$target/SHA256SUMS" \
  || { echo Unable to verify GPG signatures; exit 1; }
echo "-> Checksumming ISO"
( cd "$target" || exit 1; sha256sum -c SHA256SUMS --ignore-missing; ) \
  || { echo Unable to verify downloaded ISO; exit 1; }

# install required packages
sudo apt-get update  --quiet=2
sudo apt-get install --quiet=2 --option=Dpkg::Use-Pty=0 xorriso syslinux-utils

# Make "local" copy of ISO
# NB: Linux can't loop mount from the vboxfs mount
echo "-> Copying ISO"
rsync -Pia "$target/$download_file" "$HOME"

# create working folders
echo "-> Mounting ISO file"
mkdir -p "$tmp/iso_org"
mkdir -p "$tmp/iso_new"
mkdir "$tmp/up"
mkdir "$tmp/work"

# mount the image
sudo mount -o "loop,ro" "$HOME/$download_file" "$tmp/iso_org"
sudo mount -t overlay overlay -o "lowerdir=$tmp/iso_org,upperdir=$tmp/up,workdir=$tmp/work" "$tmp/iso_new"

# set the language for the installation menu
echo en | sudo tee "$tmp/iso_new/isolinux/lang" > /dev/null

#16.04
#taken from https://github.com/fries/prepare-ubuntu-unattended-install-iso/blob/master/make.sh
sudo sed -i -r 's/timeout\s+[0-9]+/timeout 1/g' "$tmp/iso_new/isolinux/isolinux.cfg"

# add the autoinstall option to the menu
sudo sed -i "/label install/ilabel autoinstall\\n\
  menu label ^Autoinstall Ubuntu Server\\n\
  kernel /install/vmlinuz\\n\
  append initrd=/install/initrd.gz auto=true preseed/url=$PRESEED_SERVER netcfg/get_hostname=unassigned-hostname quiet ---" "$tmp/iso_new/isolinux/txt.cfg"

echo "-> Mastering new ISO"
cd "$tmp/iso_new" || exit 1
xorrisofs -D -r -V "Ubuntu-Server 18.04 LTS amd64" -cache-inodes -J -l -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -quiet -o "$target/$new_iso_name" .
isohybrid "$target/$new_iso_name"

# print info to user
echo "<- Finished."
echo "<- $new_iso_name"
