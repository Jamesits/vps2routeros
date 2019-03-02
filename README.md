# vps2routeros

This script will wipe your current OS then install RouterOS on the target computer without requiring physical access. It has been proven to work with a wide range of VPSs.

This project is previously hosted on a [Gist](https://gist.github.com/Jamesits/6f208ce814e815c1da39726c873de152), but the script become larger over time and a gist can not fit it anymore, so it is moved here.

## WARNING

> Your warranty is now void. I am not responsible for bricked devices, dead SD cards, thermonuclear war, or you getting fired because the alarm app failed. Please do some research if you have any concerns about features included in this ROM before flashing it! YOU are choosing to make these modifications, and if you point the finger at me for messing up your device, I will laugh at you.

* **PLEASE READ THIS DOCUMENTATION THROUGHLY BEFORE RUNNING**
* CAUTION: ALL DATA ON YOUR DEVICE WILL BE LOST INSTANTLY! There is no way to get them back.
* Please make a backup of your existing network configuration prior to running this in case of any problem
* If you use IPv6, remember your gateway link-local address too
* Please SET AN PASSWORD IMMEDIATELY after installation
* Please UPDATE IMMEDIATELY after installation

## Usage

### Requirements

The target device:

* is amd64 (sometimes called x86_64) architecture
* is a physical device or a full-virtualized VM
* runs Ubuntu 16.04 or higher (we recommend Ubuntu 16.04; other distros are not tested)

Here is a [VPS provider compatibility list](wiki/Compatibility-List). Contribution is welcomed.

### Running the script

1\. download this script to the target computer:

```shell
# use wget
wget https://go.swineson.me/vps2routeros

# or use curl
curl -L https://go.swineson.me/vps2routeros
```

2\. Use any text editor to open the script, change the default config if needed

3\. run it:

```shell
chmod +x ./vps2routeros
sudo ./vps2routeros
```

4\. Set a password:

Login with WinBox or HTTP or SSH using username `admin` and an empty password, then change the password.

## Documentation

* [A detailed explanation of this script written by me](https://blog.swineson.me/install-routeros-on-any-ubuntu-vps/) (in Chinese)
* This script is originated from [this post on DigitalOcean forum](https://www.digitalocean.com/community/questions/installing-mikrotik-routeros)

## Donation

If this project is helpful to you, please consider buying me a coffee.

[![Buy Me A Coffee](https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png)](https://www.buymeacoffee.com/Jamesits) or [PayPal](https://paypal.me/Jamesits)
