#!/usr/bin/env bash
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run this test as root in a disposable Linux container." >&2; exit 1; }
root=$(cd "$(dirname "$0")/.." && pwd)
script="$root/scripts/offline-packages.sh"
tmp=$(mktemp -d)
cleanup() {
    [[ -n ${tmp:-} && -d $tmp ]] && rm -rf -- "$tmp"
}
mkdir "$tmp/bin" "$tmp/etc" "$tmp/keyrings"
trap cleanup EXIT

reject() {
    local expected=$1
    shift
    if bash "$script" "$@" >"$tmp/output" 2>&1; then
        echo "Unexpected success: $*" >&2
        exit 1
    fi
    grep -Fq "$expected" "$tmp/output" || {
        cat "$tmp/output" >&2
        exit 1
    }
}

reject "Invalid package name" download "$tmp/not-created" 'vti-libscanner;bad'
printf 'different-distribution\n0\ndeb\namd64\n' > "$tmp/platform"
printf 'vti-libscanner\n' > "$tmp/requested"
(cd "$tmp" && sha256sum platform requested > SHA256SUMS)
reject "does not match this machine" install "$tmp"
printf 'tampered\n' >> "$tmp/requested"
reject "checksum verification failed" install "$tmp"

cat > "$tmp/bin/dpkg" <<'EOF'
#!/usr/bin/env bash
echo amd64
EOF
cat > "$tmp/bin/dpkg-deb" <<'EOF'
#!/usr/bin/env bash
case "$3" in
    Architecture) echo i386 ;;
    Multi-Arch) echo same ;;
    Package) echo example-runtime ;;
    *) exit 1 ;;
esac
EOF
cat > "$tmp/bin/apt-get" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_TRACE"
for arg in "$@"; do
    case "$arg" in
        Dir::Cache::archives=*) touch "${arg#*=}/foreign.deb" ;;
    esac
done
EOF
cat > "$tmp/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf 'mock-armored-key\n'
EOF
cat > "$tmp/bin/gpg" <<'EOF'
#!/usr/bin/env bash
out=""
while (( $# > 0 )); do
    if [[ $1 == -o ]]; then
        out=$2
        shift 2
    else
        shift
    fi
done
cat > "$out"
EOF
cat > "$tmp/bin/dpkg-scanpackages" <<'EOF'
#!/usr/bin/env bash
printf 'Package: example-runtime\n'
EOF
chmod +x "$tmp/bin/"*
export TEST_TRACE="$tmp/trace"
export VTI_DEB_KEYRING="$tmp/keyrings/vti-archive-keyring.gpg"
export VTI_DEB_LIST="$tmp/etc/vti.list"
export VTI_REPO_URL="https://example.invalid/vti-linux-packages"
PATH="$tmp/bin:$PATH" bash "$script" download "$tmp/bundle" example-runtime:i386 vti-libscanner.x86_64
[[ -s $VTI_DEB_KEYRING ]]
[[ -s $VTI_DEB_LIST ]]
[[ -s $tmp/bundle/keys/vti-archive-keyring.gpg ]]
[[ $(grep -c -- '--download-only' "$tmp/trace") == 2 ]]
grep -q 'example-runtime:amd64' "$tmp/trace"

rm -f -- "$VTI_DEB_KEYRING"
PATH="$tmp/bin:$PATH" bash "$script" install "$tmp/bundle"
[[ $(cat "$VTI_DEB_KEYRING") == "mock-armored-key" ]]

printf 'existing-key\n' > "$VTI_DEB_KEYRING"
PATH="$tmp/bin:$PATH" bash "$script" install "$tmp/bundle"
[[ $(cat "$VTI_DEB_KEYRING") == "existing-key" ]]
echo "Offline bundle validation tests passed."
