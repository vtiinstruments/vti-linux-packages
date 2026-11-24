# VTI Linux package repository

This public GitHub Pages repository distributes signed VTI Linux packages.
Product source remains in its source repository; this repository contains
only published package files, repository metadata, public signing keys, and
the automation that publishes them.

The repository includes VTEX10xxA PnP, libVTEX and VTI instrument driver
packages. The instrument driver build 145 is available for amd64 and x86_64;
its legacy 32-bit packages are signed release assets but not repository-indexed
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

APT verifies the signed repository metadata. The published DEB packages also
carry `dpkg-sig` signatures. Install a 32-bit driver alongside the 64-bit
driver with:

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

The RPM packages and repository metadata are signed and verified by DNF.
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

## Publishing

The private product repository builds packages on a version-tag push or a
manual workflow dispatch, then uploads them to a draft release here. This
repository signs the packages and repository metadata, updates the GitHub
Pages branch, and publishes the release only after those steps succeed.

Configure these Actions secrets in this repository before the first publish:

- `VTI_PACKAGE_SIGNING_KEY`: ASCII-armored private GPG key.
- `VTI_PACKAGE_SIGNING_PASSPHRASE`: its passphrase.

Configure these secrets in the private `VTEX10xxA-PnP-Driver` source
repository. The GitHub App must be installed on `vti-ppa` with repository
Contents write permission; the workflow creates a short-lived installation
token for each release:

- `VTI_PPA_APP_ID`: the GitHub App ID.
- `VTI_PPA_APP_PRIVATE_KEY`: the GitHub App private key in PEM format.

The private `nextgen-libVTEX` source repository uses the same App secrets.
Publishing a non-prerelease GitHub release tagged `vMAJOR.MINOR.BUILD` builds
and verifies the packages, then uploads them to a `libvtex-vMAJOR.MINOR.BUILD`
draft release here. The namespaced tag prevents collisions with other products.
The publishing workflow validates and signs the full libVTEX package set before
updating the repositories. Prereleases and failed builds are not published.

For instrument driver packages, upload the complete 32-bit and 64-bit DEB
and RPM package set to a release tagged `spiderman-build-<build-number>`,
then run the publishing workflow with that tag. All package versions must
end in the build number. Legacy `x86` packages are signed as release assets,
but excluded from repository indexes until rebuilt as `i386` and `i686`.

Enable GitHub Pages for this repository from the `gh-pages` branch, root
directory. Do not commit any private signing or GitHub App keys.
