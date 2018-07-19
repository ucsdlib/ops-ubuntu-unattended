Unattended Ubuntu ISO
=====================

Steps:

1. Clone this repo
3. `vagrant up`
4. `vagrant ssh -c /vagrant/create-unattended-iso.sh` 
4. (Alternative) `vagrant ssh -c 'PRESEED_SERVER=preseed.example.org /vagrant/create-unattended-iso.sh'`
5. Enjoy!

The script will download Ubuntu 18.04 from Canonical, along with the SHA256 sums and the GPG signatures.
The GPG signatures are verified, then the ISO is checksummed to provide assurance the correct ISO is used.
