#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 || ! $1 =~ ^discovery-tool-v([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    echo "Usage: $0 discovery-tool-vMAJOR.MINOR.PATCH <incoming-dir>" >&2
    exit 2
fi
expected_version="${BASH_REMATCH[1]}-1"
incoming=$2
mapfile -t debs < <(find "$incoming" -maxdepth 1 -type f -name '*.deb' -print | sort)
mapfile -t rpms < <(find "$incoming" -maxdepth 1 -type f -name '*.rpm' -print | sort)
mapfile -t archives < <(find "$incoming" -maxdepth 1 -type f -name '*.tar.gz' -print | sort)
if [[ ${#debs[@]} -ne 1 || ${#rpms[@]} -ne 1 || ${#archives[@]} -ne 0 ]]; then
    echo "Expected one amd64 DEB, one x86_64 RPM, and no tarballs." >&2
    exit 1
fi

deb=${debs[0]}
if [[ $(dpkg-deb -f "$deb" Package) != discovery-tool ||
      $(dpkg-deb -f "$deb" Version) != "$expected_version" ||
      $(dpkg-deb -f "$deb" Architecture) != amd64 ]]; then
    echo "Unexpected DEB name, version, or architecture: $deb" >&2
    exit 1
fi

rpm=${rpms[0]}
if [[ $(rpm -qp --qf '%{NAME}' "$rpm") != discovery-tool ||
      $(rpm -qp --qf '%{VERSION}-%{RELEASE}' "$rpm") != "$expected_version" ||
      $(rpm -qp --qf '%{ARCH}' "$rpm") != x86_64 ]]; then
    echo "Unexpected RPM name, version, or architecture: $rpm" >&2
    exit 1
fi
echo "Validated Discovery Tool package set for $1."
