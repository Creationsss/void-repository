# Void Repository

A third-party Void Linux binary package repository.

Browse the package list, grouped by category with live version status, at
[void.creations.works](https://void.creations.works).

## Setup

Add the repo:

```sh
echo "repository=https://void.creations.works" | sudo tee /etc/xbps.d/creations.conf
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
