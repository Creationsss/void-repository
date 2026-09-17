# Void Repository

A third-party Void Linux binary package repository.

Browse the package list, grouped by category with live version status, at
[void.creations.works](https://void.creations.works).

## Setup

Add the repo:

```sh
echo "repository=https://void.creations.works" | sudo tee /etc/xbps.d/00-creations.conf
```

The `00-` prefix matters if you plan to use any package that also exists in the
official Void repos (for example the Hyprland stack). xbps registers repos in
filename order and prefers the first one that has a package, regardless of
version, so a config that sorts after `00-repository-main.conf` lets Void's
older copy shadow the newer build here. Naming the file `00-creations.conf`
keeps it ahead of the main repo. If you already added it as `creations.conf`,
rename it:

```sh
sudo mv /etc/xbps.d/creations.conf /etc/xbps.d/00-creations.conf
sudo xbps-install -S
```

Install a package:

```sh
sudo xbps-install -S <package>
```

The first time you install a package, xbps asks to import this repo's signing
key. Answer `Y` to trust it.

Updates come through normally with:

```sh
sudo xbps-install -Su
```
