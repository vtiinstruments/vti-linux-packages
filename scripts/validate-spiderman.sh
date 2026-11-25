#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 || ! $1 =~ ^spiderman-build-([0-9]+)$ ]]; then
    echo "Usage: $0 spiderman-build-<number> <incoming-dir>" >&2
    exit 2
fi
build_number=${BASH_REMATCH[1]}
incoming=$2
mapfile -t debs < <(find "$incoming" -maxdepth 1 -type f -name '*.deb' -print | sort)
mapfile -t rpms < <(find "$incoming" -maxdepth 1 -type f -name '*.rpm' -print | sort)
mapfile -t archives < <(find "$incoming" -maxdepth 1 -type f -name '*.tar.gz' -print | sort)
if [[ ${#debs[@]} -ne 14 || ${#rpms[@]} -ne 14 || ${#archives[@]} -ne 0 ]]; then
    echo "Expected 14 DEBs, 14 RPMs, and no tarballs." >&2
    exit 1
fi

declare -A expected versions
for name in common digitizer dsa platform switch dio varres; do
    for kind in deb64 deb32 rpm64 rpm32; do
        expected["vti-lib${name}:$kind"]=1
    done
done

record() {
    local name=$1 kind=$2 version=$3 key="$1:$2"
    if [[ ${expected[$key]:-} != 1 || $version != *".$build_number" ]]; then
        echo "Unexpected or duplicate package: $key ($version)" >&2
        exit 1
    fi
    unset 'expected[$key]'
    if [[ ${versions[$name]+present} && ${versions[$name]} != "$version" ]]; then
        echo "Inconsistent versions for $name" >&2
        exit 1
    fi
    versions[$name]=$version
}

for package in "${debs[@]}"; do
    name=$(dpkg-deb -f "$package" Package)
    architecture=$(dpkg-deb -f "$package" Architecture)
    version=$(dpkg-deb -f "$package" Version)
    case "$architecture" in
        amd64) kind=deb64 ;;
        i386) kind=deb32 ;;
        *) echo "Unexpected DEB architecture: $architecture" >&2; exit 1 ;;
    esac
    record "$name" "$kind" "$version"
done
for package in "${rpms[@]}"; do
    name=$(rpm -qp --qf '%{NAME}' "$package")
    architecture=$(rpm -qp --qf '%{ARCH}' "$package")
    version=$(rpm -qp --qf '%{VERSION}' "$package")
    release=$(rpm -qp --qf '%{RELEASE}' "$package")
    [[ $release == 1 ]] || { echo "Unexpected RPM release: $release" >&2; exit 1; }
    case "$architecture" in
        x86_64) kind=rpm64 ;;
        i686) kind=rpm32 ;;
        *) echo "Unexpected RPM architecture: $architecture" >&2; exit 1 ;;
    esac
    record "$name" "$kind" "$version"
done
if (( ${#expected[@]} )); then
    echo "Missing required Spiderman packages." >&2
    exit 1
fi
echo "Validated Spiderman package set for build $build_number."
