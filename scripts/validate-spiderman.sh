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
mapfile -t ipks < <(find "$incoming" -maxdepth 1 -type f -name '*.ipk' -print | sort)
mapfile -t archives < <(find "$incoming" -maxdepth 1 -type f -name '*.tar.gz' -print | sort)
if [[ ${#debs[@]} -ne 14 || ${#rpms[@]} -ne 14 ||
      ( ${#ipks[@]} -ne 3 && ${#ipks[@]} -ne 6 ) || ${#archives[@]} -ne 0 ]]; then
    echo "Expected 14 DEBs, 14 RPMs, 3 or 6 NI RT IPKs, and no tarballs." >&2
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

declare -A expected_ipks versions_ipk
for arch in x64; do
    for name in commonrt dsart platformrt; do
        expected_ipks["vti-lib${name}:$arch"]=1
    done
done
if (( ${#ipks[@]} == 6 )); then
    for name in commonrt dsart platformrt; do
        expected_ipks["vti-lib${name}:arm"]=1
    done
fi

for package in "${ipks[@]}"; do
    control=$(ar p "$package" control.tar.gz | tar -xzOf - ./control) || {
        echo "Cannot read NI RT package control data: $package" >&2
        exit 1
    }
    name=$(awk -F ': ' '$1 == "Package" { print $2; exit }' <<< "$control")
    version=$(awk -F ': ' '$1 == "Version" { print $2; exit }' <<< "$control")
    architecture=$(awk -F ': ' '$1 == "Architecture" { print $2; exit }' <<< "$control")
    key="$name:$architecture"
    if [[ ${expected_ipks[$key]:-} != 1 || $version != *".$build_number" ]]; then
        echo "Unexpected or duplicate NI RT package: $key ($version)" >&2
        exit 1
    fi
    unset 'expected_ipks[$key]'
    if [[ ${versions_ipk[$name]+present} && ${versions_ipk[$name]} != "$version" ]]; then
        echo "Inconsistent NI RT versions for $name" >&2
        exit 1
    fi
    versions_ipk[$name]=$version
done
if (( ${#expected_ipks[@]} )); then
    echo "Missing required NI RT packages." >&2
    exit 1
fi
echo "Validated Spiderman package set for build $build_number."
