# VTI Linux package repository

This public GitHub Pages repository provides VTI Linux packages for
installation through APT and DNF.

The repository includes VTEX10xxA PnP, libVTEX and VTI instrument driver
packages. The instrument driver build 145 is available for amd64 and x86_64;
its legacy 32-bit packages are release assets but not repository-indexed
because they have incorrect architecture labels.

## Install

### Ubuntu and Debian

Enable the i386 architecture if you need to run 32-bit applications:

```sh
sudo dpkg --add-architecture i386
sudo apt update
```

Install the repository key and source:

```sh
curl -fsSL https://vtiinstruments.github.io/vti-ppa/public.key \
  | sudo gpg --dearmor -o /usr/share/keyrings/vti-archive-keyring.gpg
echo "deb [arch=amd64,i386 signed-by=/usr/share/keyrings/vti-archive-keyring.gpg] https://vtiinstruments.github.io/vti-ppa stable main" \
  | sudo tee /etc/apt/sources.list.d/vti.list
sudo apt update
sudo apt install vtex10xxa-pnp
```

For libVTEX, install a driver such as `sudo apt install vti-libscanner`.
Its required `vti-libvtex-common` headers are installed automatically.
For VTI instrument drivers, install a package such as `vti-libdsa`; its
`vti-libcommon` dependency is installed automatically.
For Discovery Tool, install `discovery-tool` (amd64 only).

Install a 32-bit driver alongside the 64-bit driver with:

```sh
sudo apt install vtex10xxa-pnp:i386
```

### RHEL, Rocky Linux, AlmaLinux, and Fedora

Import the package-signing key and configure the repository:

```sh
sudo rpm --import https://vtiinstruments.github.io/vti-ppa/RPM-GPG-KEY-VTI
sudo curl -fsSL https://vtiinstruments.github.io/vti-ppa/vti.repo \
  -o /etc/yum.repos.d/vti.repo
sudo dnf install vtex10xxa-pnp
```

For libVTEX, install a driver such as `sudo dnf install vti-libscanner`.
For VTI instrument drivers, install a package such as `vti-libdsa`.
For Discovery Tool, install `discovery-tool` (x86_64 only).

Install the 32-bit variant alongside x86_64 with:

```sh
sudo dnf install vtex10xxa-pnp.i686
```

Normal `apt upgrade` and `dnf upgrade` operations install later releases.

## Compatibility

The VTEX10xxA PnP driver packages are built on Debian 12 and target Ubuntu 22.04/24.04,
Debian 12, RHEL/Rocky/AlmaLinux 9, and current Fedora releases. The Linux
Tauri front panel is not included because WebKitGTK 4.1 is not available on
all supported systems.

libVTEX packages are built on Ubuntu 22.04 and verified using Ubuntu and
AlmaLinux 9 containers for both architectures.
Compatibility of the instrument driver packages with specific distributions
has not yet been established. Their 32-bit and 64-bit packages use the same
installation paths and are not intended to be installed together.
