# VTI Linux Packages

Linux driver packages for VTI Instruments hardware on Debian/Ubuntu (`apt`) and RHEL/Rocky/AlmaLinux/Fedora (`dnf`).

**CPU requirement:** Intel Sandy Bridge or newer processor (AVX support required for both 32-bit and 64-bit packages).

---

## 1. Add the package repository

### Ubuntu / Debian

```sh
curl -fsSL https://vtiinstruments.github.io/vti-linux-packages/public.key \
  | sudo gpg --batch --yes --dearmor -o /usr/share/keyrings/vti-archive-keyring.gpg

echo "deb [arch=amd64,i386 signed-by=/usr/share/keyrings/vti-archive-keyring.gpg] https://vtiinstruments.github.io/vti-linux-packages stable main" \
  | sudo tee /etc/apt/sources.list.d/vti.list

sudo apt update
```

### RHEL / Rocky Linux / AlmaLinux / Fedora

```sh
sudo rpm --import https://vtiinstruments.github.io/vti-linux-packages/RPM-GPG-KEY-VTI
sudo curl -fsSL https://vtiinstruments.github.io/vti-linux-packages/vti.repo \
  -o /etc/yum.repos.d/vti.repo
sudo dnf makecache
```

---

## 2. Find your package

Pick the package name for your instrument from the table below. Package names are case-sensitive (`vti-libRTDSimulator` and `vti-libBreadboard` use capital letters on DNF). Shared VTI dependency packages are installed automatically.

| Instrument | Function | APT package | DNF package | Architectures |
|---|---|---|---|---|
| EX1200, EX7000 | System and chassis | `vti-libsystem` | `vti-libsystem` | 32-bit, 64-bit |
| EX1200 | Scanner | `vti-libscanner` | `vti-libscanner` | 32-bit, 64-bit |
| EX1200 | Digital multimeter (DMM) | `vti-libdmm` | `vti-libdmm` | 32-bit, 64-bit |
| EX1200-7416 | Comparator | `vti-libcomparator` | `vti-libcomparator` | 32-bit, 64-bit |
| EX1200-1538 | Multifunction | `vti-libmultifunction` | `vti-libmultifunction` | 32-bit, 64-bit |
| EX1200 | RTD simulator | `vti-librtdsimulator` | `vti-libRTDSimulator` | 32-bit, 64-bit |
| EX1200-7000 | Breadboard | `vti-libbreadboard` | `vti-libBreadboard` | 32-bit, 64-bit |
| EX1200, EX7000, SMX | Switches | `vti-libswitch` | `vti-libswitch` | 64-bit |
| EX1200-7500, EMX | Digital I/O | `vti-libdio` | `vti-libdio` | 64-bit |
| EX1401, EX1402, EX1403/A, EMX, RX | Digitizers | `vti-libdigitizer` | `vti-libdigitizer` | 64-bit |
| EX1401, EX1402, EX1403/A, EMX, RX | Dynamic signal / data acquisition | `vti-libdsa` | `vti-libdsa` | 64-bit |
| EX1401, EX1402, EX1403/A, EMX, PMX | Platform / PXIe | `vti-libplatform` | `vti-libplatform` | 64-bit |
| Variable resistance modules | Variable resistance | `vti-libvarres` | `vti-libvarres` | 64-bit |

> **Note:** `vtex10xxa-pnp` (EX10xxA / EX10xxB) and `discovery-tool` (64-bit only) are not published in this repository yet.

### NI Linux Real-Time

NI Linux Real-Time `.ipk` packages for `libDsaRT` and `libPlatformRT` are attached to the matching `spiderman-build-*` release in [GitHub Releases](https://github.com/vtiinstruments/vti-linux-packages/releases). Download the package set for the target's architecture (`x64` or `arm`); the shared `libcommonrt` package is included. These packages are distributed as release assets and are not part of the APT or RPM repositories.

On the NI RT target, install the downloaded packages with `opkg`, for example:

```sh
opkg install ./72-0353-600_vti-libcommonrt_<common-version>_x64.ipk \
  ./72-0368-500_vti-libdsart_<dsa-version>_x64.ipk \
  ./72-0377-600_vti-libplatformrt_<platform-version>_x64.ipk
```

---

## 3. Install packages

The examples below install `vti-libscanner` and `vti-libsystem`. Swap in or add any package names from the table above.

The commands also include the standard C/C++ runtime libraries (`libc`, `libgcc`, `libstdc++`) so that minimal and 32-bit installations have everything needed to load the drivers.

### 64-bit machine — install 64-bit packages

Ubuntu / Debian:

```sh
sudo apt install libc6:amd64 libgcc-s1:amd64 libstdc++6:amd64 \
  vti-libscanner:amd64 vti-libsystem:amd64
```

RHEL / Rocky / AlmaLinux / Fedora:

```sh
sudo dnf install glibc.x86_64 libgcc.x86_64 libstdc++.x86_64 \
  vti-libscanner.x86_64 vti-libsystem.x86_64
```

Example for EX1401/EX1402/EX1403 data acquisition and platform drivers:

```sh
# Ubuntu / Debian
sudo apt install libc6:amd64 libgcc-s1:amd64 libstdc++6:amd64 \
  vti-libdsa:amd64 vti-libplatform:amd64

# RHEL / Rocky / AlmaLinux / Fedora
sudo dnf install glibc.x86_64 libgcc.x86_64 libstdc++.x86_64 \
  vti-libdsa.x86_64 vti-libplatform.x86_64
```

### 64-bit machine — install 32-bit packages

Ubuntu / Debian (enable `i386` once first):

```sh
sudo dpkg --add-architecture i386
sudo apt update
sudo apt install libc6:i386 libgcc-s1:i386 libstdc++6:i386 \
  vti-libscanner:i386 vti-libsystem:i386
```

RHEL / Rocky / AlmaLinux / Fedora:

```sh
sudo dnf install glibc.i686 libgcc.i686 libstdc++.i686 \
  vti-libscanner.i686 vti-libsystem.i686
```

### 32-bit machine — install 32-bit packages

Ubuntu / Debian:

```sh
sudo apt install libc6:i386 libgcc-s1:i386 libstdc++6:i386 \
  vti-libscanner:i386 vti-libsystem:i386
```

RHEL / Rocky / AlmaLinux / Fedora (on a distro release that supports 32-bit):

```sh
sudo dnf install glibc.i686 libgcc.i686 libstdc++.i686 \
  vti-libscanner.i686 vti-libsystem.i686
```

### 64-bit machine — install both 32-bit and 64-bit packages

The drivers in the table above install files to shared paths under `/opt/vti`, so you cannot install both the 32-bit and 64-bit versions of the same package at the same time. Install one architecture per machine (or use a container/chroot for the other).

When `vtex10xxa-pnp` is published, it supports installing both architectures side by side:

```sh
# Ubuntu / Debian (enable i386 first as shown above)
sudo apt install vtex10xxa-pnp:amd64 vtex10xxa-pnp:i386

# RHEL / Rocky / AlmaLinux / Fedora
sudo dnf install vtex10xxa-pnp.x86_64 vtex10xxa-pnp.i686
```

### Updating packages

Use normal system updates (`sudo apt upgrade` or `sudo dnf upgrade`) to get newer driver releases.

---

## Offline / air-gapped installation

You can use [scripts/offline-packages.sh](./scripts/offline-packages.sh) to download packages and their dependencies on an internet-connected Linux machine, then install them on an air-gapped machine. The script also bundles the VTI signing key and installs it automatically if it is not installed yet.

**Before you start:**
- Both machines must run the **same Linux distribution, version, and OS architecture** (for example, both Ubuntu 22.04 `amd64`).
- If you are installing 32-bit (`i386`) packages on 64-bit Ubuntu/Debian, run `sudo dpkg --add-architecture i386` on **both** machines first.

### Step 1: Install packaging tools (connected machine)

```sh
# Ubuntu / Debian
sudo apt install curl gpg dpkg-dev

# RHEL / Rocky / AlmaLinux / Fedora
sudo dnf install curl createrepo_c dnf-plugins-core
```

### Step 2: Download the bundle (connected machine)

Choose a new folder path (for example `/var/tmp/vti-bundle`) and list the packages you need. If the VTI repository and key are not configured on the connected machine yet, the script sets them up automatically.

```sh
# Ubuntu / Debian example (64-bit)
sudo bash scripts/offline-packages.sh download /var/tmp/vti-bundle \
  libc6:amd64 libgcc-s1:amd64 libstdc++6:amd64 \
  vti-libscanner:amd64 vti-libsystem:amd64

# Ubuntu / Debian example (32-bit packages for a 64-bit or 32-bit machine)
sudo bash scripts/offline-packages.sh download /var/tmp/vti-bundle \
  libc6:i386 libgcc-s1:i386 libstdc++6:i386 \
  vti-libscanner:i386 vti-libsystem:i386

# RHEL / Rocky / AlmaLinux / Fedora example
sudo bash scripts/offline-packages.sh download /var/tmp/vti-bundle \
  glibc.x86_64 libgcc.x86_64 libstdc++.x86_64 \
  vti-libscanner.x86_64 vti-libsystem.x86_64
```

### Step 3: Install on the air-gapped machine

Copy `offline-packages.sh` and the `/var/tmp/vti-bundle` directory to the offline machine (keep it in a path without spaces, such as `/var/tmp/vti-bundle`), then run:

```sh
sudo bash offline-packages.sh install /var/tmp/vti-bundle
```
