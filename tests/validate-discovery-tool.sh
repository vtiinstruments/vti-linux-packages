#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
cleanup() {
    rm -f "$tmp/bin/dpkg-deb" "$tmp/bin/rpm" "$tmp/incoming/package.deb" \
        "$tmp/incoming/package.rpm" "$tmp/incoming/extra.deb" "$tmp/incoming/extra.tar.gz"
    rmdir "$tmp/bin" "$tmp/incoming" "$tmp"
}
trap cleanup EXIT
mkdir "$tmp/bin" "$tmp/incoming"
cat > "$tmp/bin/dpkg-deb" <<'EOF'
#!/usr/bin/env bash
case "$3" in
    Package) printf '%s' "${DEB_NAME:-discovery-tool}" ;;
    Version) printf '%s' "${DEB_VERSION:-2.0.0-1}" ;;
    Architecture) printf '%s' "${DEB_ARCH:-amd64}" ;;
    *) exit 1 ;;
esac
EOF
cat > "$tmp/bin/rpm" <<'EOF'
#!/usr/bin/env bash
case "$3" in
    '%{NAME}') printf '%s' "${RPM_NAME:-discovery-tool}" ;;
    '%{VERSION}-%{RELEASE}') printf '%s' "${RPM_VERSION:-2.0.0-1}" ;;
    '%{ARCH}') printf '%s' "${RPM_ARCH:-x86_64}" ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/dpkg-deb" "$tmp/bin/rpm"
export PATH="$tmp/bin:$PATH"
touch "$tmp/incoming/package.deb" "$tmp/incoming/package.rpm"
validator="$root/scripts/validate-discovery-tool.sh"

bash "$validator" discovery-tool-v2.0.0 "$tmp/incoming"
reject() {
    if "$@" >/dev/null 2>&1; then
        echo "Unexpected acceptance: $*" >&2
        exit 1
    fi
}
reject bash "$validator" discovery-tool-v2.0 "$tmp/incoming"
reject env DEB_NAME=other bash "$validator" discovery-tool-v2.0.0 "$tmp/incoming"
reject env DEB_VERSION=2.0.1-1 bash "$validator" discovery-tool-v2.0.0 "$tmp/incoming"
reject env DEB_ARCH=i386 bash "$validator" discovery-tool-v2.0.0 "$tmp/incoming"
reject env RPM_NAME=other bash "$validator" discovery-tool-v2.0.0 "$tmp/incoming"
reject env RPM_VERSION=2.0.0-2 bash "$validator" discovery-tool-v2.0.0 "$tmp/incoming"
reject env RPM_ARCH=i686 bash "$validator" discovery-tool-v2.0.0 "$tmp/incoming"
touch "$tmp/incoming/extra.deb"
reject bash "$validator" discovery-tool-v2.0.0 "$tmp/incoming"
rm "$tmp/incoming/extra.deb" "$tmp/incoming/package.rpm"
reject bash "$validator" discovery-tool-v2.0.0 "$tmp/incoming"
touch "$tmp/incoming/package.rpm" "$tmp/incoming/extra.tar.gz"
reject bash "$validator" discovery-tool-v2.0.0 "$tmp/incoming"
echo "Discovery Tool validation tests passed."
