#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 download BUNDLE PACKAGE [PACKAGE ...]" >&2
    echo "       $0 install BUNDLE" >&2
    exit 2
}

die() { echo "Error: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || die "Required tool missing: $1"; }
fetch() {
    if command -v curl >/dev/null; then
        curl -fsSL "$1"
    elif command -v wget >/dev/null; then
        wget -qO- "$1"
    else
        die "Required tool missing: curl or wget"
    fi
}
[[ $# -ge 2 ]] || usage
mode=$1
bundle=$2
shift 2
[[ $EUID -eq 0 ]] || die "Run as root, including the download step."
[[ -r /etc/os-release ]] || die "Cannot determine operating system."
# shellcheck source=/dev/null
source /etc/os-release
[[ -n ${ID:-} && -n ${VERSION_ID:-} ]] || die "OS ID and version are required."

repo_url=${VTI_REPO_URL:-https://vtiinstruments.github.io/vti-linux-packages}
deb_keyring=${VTI_DEB_KEYRING:-/usr/share/keyrings/vti-archive-keyring.gpg}
deb_list=${VTI_DEB_LIST:-/etc/apt/sources.list.d/vti.list}
rpm_repo=${VTI_RPM_REPO:-/etc/yum.repos.d/vti.repo}
vti_fpr=e348deaabd12d845b0e9a996e3a8dff5423c357f

rpm_has_vti_key() {
    rpm -qa 'gpg-pubkey*' 2>/dev/null | grep -Eqi "gpg-pubkey-(${vti_fpr}|${vti_fpr: -8})-"
}

if command -v apt-get >/dev/null && command -v dpkg >/dev/null; then
    kind=deb
    machine_arch=$(dpkg --print-architecture)
elif command -v dnf >/dev/null && command -v rpm >/dev/null; then
    kind=rpm
    machine_arch=$(rpm --eval '%{_arch}')
else
    die "APT/dpkg or DNF/rpm is required."
fi

case "$mode" in
    download)
        (( $# > 0 )) || usage
        [[ ! -e $bundle ]] || die "Bundle path already exists: $bundle"
        for package in "$@"; do
            [[ $package =~ ^[a-zA-Z0-9][a-zA-Z0-9._+:-]*$ ]] || die "Invalid package name: $package"
        done
        need sha256sum
        need gzip
        mkdir -p "$bundle/packages" "$bundle/keys"
        bundle=$(cd "$bundle" && pwd -P)
        printf '%s\n' "$ID" "$VERSION_ID" "$kind" "$machine_arch" > "$bundle/platform"
        printf '%s\n' "$@" > "$bundle/requested"
        if [[ $kind == deb ]]; then
            need dpkg-scanpackages
            if [[ ! -s $deb_keyring ]]; then
                need gpg
                install -d -m 0755 "$(dirname "$deb_keyring")"
                fetch "$repo_url/public.key" | gpg --batch --yes --dearmor -o "$deb_keyring"
                chmod 0644 "$deb_keyring"
            fi
            if [[ ! -f $deb_list ]] && ! grep -RqsF "$repo_url" /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
                install -d -m 0755 "$(dirname "$deb_list")"
                printf 'deb [arch=amd64,i386 signed-by=%s] %s stable main\n' "$deb_keyring" "$repo_url" > "$deb_list"
            fi
            cp "$deb_keyring" "$bundle/keys/vti-archive-keyring.gpg"
            mkdir -p "$bundle/cache/archives/partial"
            if id -u _apt >/dev/null 2>&1; then
                chown _apt:root "$bundle/cache/archives/partial"
            fi
            : > "$bundle/empty-status"
            apt-get -o APT::Update::Error-Mode=any update
            shopt -s nullglob
            resolve=("$@")
            declare -A native_pairs=()
            while :; do
                apt-get -y --no-install-recommends --download-only \
                    -o "Dir::State::status=$bundle/empty-status" \
                    -o "Dir::Cache::archives=$bundle/cache/archives" install "${resolve[@]}"
                added=0
                for file in "$bundle/cache/archives/"*.deb; do
                    architecture=$(dpkg-deb -f "$file" Architecture)
                    multiarch=$(dpkg-deb -f "$file" Multi-Arch)
                    if [[ $architecture != "$machine_arch" && $architecture != all && $multiarch == same ]]; then
                        name=$(dpkg-deb -f "$file" Package)
                        if [[ -z ${native_pairs[$name]:-} ]]; then
                            native_pairs[$name]=1
                            resolve+=("$name:$machine_arch")
                            added=1
                        fi
                    fi
                done
                (( added )) || break
            done
            files=("$bundle/cache/archives/"*.deb)
            (( ${#files[@]} > 0 )) || die "No DEB packages were downloaded."
            mv "${files[@]}" "$bundle/packages/"
            (cd "$bundle/packages" && dpkg-scanpackages --multiversion . /dev/null > Packages && gzip -n -k Packages)
            rm -f "$bundle/empty-status" "$bundle/cache/archives/lock"
            rmdir "$bundle/cache/archives/partial" "$bundle/cache/archives" "$bundle/cache"
        else
            need createrepo_c
            fetch "$repo_url/RPM-GPG-KEY-VTI" > "$bundle/keys/RPM-GPG-KEY-VTI"
            if ! rpm_has_vti_key; then
                rpm --import "$bundle/keys/RPM-GPG-KEY-VTI"
            fi
            if [[ ! -f $rpm_repo ]]; then
                install -d -m 0755 "$(dirname "$rpm_repo")"
                fetch "$repo_url/vti.repo" > "$rpm_repo"
            fi
            dnf -y download --resolve --alldeps --destdir "$bundle/packages" "$@"
            shopt -s nullglob
            files=("$bundle/packages/"*.rpm)
            (( ${#files[@]} > 0 )) || die "No RPM packages were downloaded."
            createrepo_c "$bundle/packages"
        fi
        (cd "$bundle" && find platform requested keys packages -type f -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
        echo "Bundle created at $bundle."
        ;;
    install)
        (( $# == 0 )) || usage
        need sha256sum
        [[ -d $bundle ]] || die "Bundle directory not found."
        bundle=$(cd "$bundle" && pwd -P)
        [[ -r $bundle/platform && -r $bundle/requested && -r $bundle/SHA256SUMS ]] || die "Incomplete bundle."
        (cd "$bundle" && sha256sum --check SHA256SUMS) || die "Bundle checksum verification failed."
        mapfile -t platform < "$bundle/platform"
        [[ ${#platform[@]} == 4 && ${platform[0]} == "$ID" && ${platform[1]} == "$VERSION_ID" \
            && ${platform[2]} == "$kind" && ${platform[3]} == "$machine_arch" ]] \
            || die "Bundle OS, version, package manager or native architecture does not match this machine."
        mapfile -t packages < "$bundle/requested"
        (( ${#packages[@]} > 0 )) || die "No packages requested."
        for package in "${packages[@]}"; do
            [[ $package =~ ^[a-zA-Z0-9][a-zA-Z0-9._+:-]*$ ]] || die "Invalid package name in bundle."
        done
        if [[ $kind == deb ]]; then
            [[ $bundle =~ ^/[a-zA-Z0-9._/-]+$ ]] || die "APT bundle path contains unsupported characters."
            if [[ -s $bundle/keys/vti-archive-keyring.gpg && ! -s $deb_keyring ]]; then
                install -d -m 0755 "$(dirname "$deb_keyring")"
                install -m 0644 "$bundle/keys/vti-archive-keyring.gpg" "$deb_keyring"
            fi
            source_list=$(mktemp)
            apt_lists=$(mktemp -d)
            trap 'rm -f -- "$source_list"; find "$apt_lists" -mindepth 1 -delete; rmdir "$apt_lists"' EXIT
            chmod 755 "$apt_lists"
            mkdir "$apt_lists/partial"
            printf 'deb [trusted=yes] file:%s/packages ./\n' "$bundle" > "$source_list"
            chmod 644 "$source_list"
            apt-get -o APT::Sandbox::User=root -o APT::Update::Error-Mode=any \
                -o "Dir::Etc::sourcelist=$source_list" \
                -o Dir::Etc::sourceparts=- -o "Dir::State::lists=$apt_lists" update
            apt-get -y -o APT::Sandbox::User=root -o "Dir::Etc::sourcelist=$source_list" \
                -o Dir::Etc::sourceparts=- -o "Dir::State::lists=$apt_lists" install "${packages[@]}"
        else
            if [[ -s $bundle/keys/RPM-GPG-KEY-VTI ]] && ! rpm_has_vti_key; then
                rpm --import "$bundle/keys/RPM-GPG-KEY-VTI"
            fi
            shopt -s nullglob
            rpm_files=("$bundle/packages/"*.rpm)
            if (( ${#rpm_files[@]} > 0 )) && ! rpm -K "${rpm_files[@]}" >/dev/null 2>&1; then
                while IFS= read -r key_uri; do
                    key_path=${key_uri#file://}
                    key_path=${key_path//\$releasever/$VERSION_ID}
                    key_path=${key_path//\$basearch/$machine_arch}
                    [[ -r $key_path ]] && rpm --import "$key_path"
                done < <(grep -RhoE 'file:///etc/pki/rpm-gpg/[^ ,]+' /etc/yum.repos.d 2>/dev/null | sort -u)
            fi
            dnf -y --disablerepo='*' --repofrompath="vti-offline,file://$bundle/packages" \
                --setopt=vti-offline.gpgcheck=1 --setopt=vti-offline.repo_gpgcheck=0 \
                --setopt=vti-offline.skip_if_unavailable=False install "${packages[@]}"
        fi
        ;;
    *) usage ;;
esac
