#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
cleanup() {
    rm -rf -- "$tmp"
}
trap cleanup EXIT
mkdir -p "$tmp/bin" "$tmp/incoming"

cat > "$tmp/bin/dpkg-deb" <<'EOF'
#!/usr/bin/env bash
sed -n "s/^$3=//p" "$2"
EOF
cat > "$tmp/bin/rpm" <<'EOF'
#!/usr/bin/env bash
case "$3" in
    '%{NAME}') field=Package ;;
    '%{VERSION}') field=Version ;;
    '%{RELEASE}') field=Release ;;
    '%{ARCH}') field=Architecture ;;
    *) exit 1 ;;
esac
sed -n "s/^$field=//p" "$4"
EOF
cat > "$tmp/bin/ar" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$2"
EOF
cat > "$tmp/bin/tar" <<'EOF'
#!/usr/bin/env bash
read -r path
name=$(basename "$path" .ipk)
IFS=_ read -r _ package version architecture <<< "$name"
printf 'Package: %s\nVersion: %s\nArchitecture: %s\n' "$package" "$version" "$architecture"
EOF
chmod +x "$tmp/bin/"*
export PATH="$tmp/bin:$PATH"
validator="$root/scripts/validate-spiderman.sh"

write_deb() {
    printf 'Package=%s\nVersion=1.2.3.%s\nArchitecture=%s\n' "$1" "$build_number" "$2" > "$tmp/incoming/$1-$2.deb"
}
write_rpm() {
    printf 'Package=%s\nVersion=1.2.3.%s\nRelease=1\nArchitecture=%s\n' "$1" "$build_number" "$2" > "$tmp/incoming/$1-$2.rpm"
}
write_ipk() {
    printf 'fixture\n' > "$tmp/incoming/72-0000-000_${1}_1.2.3.${build_number}_${2}.ipk"
}
build_number=42
for name in common digitizer dsa platform switch dio varres; do
    write_deb "vti-lib$name" amd64
    write_deb "vti-lib$name" i386
    write_rpm "vti-lib$name" x86_64
    write_rpm "vti-lib$name" i686
done
for name in vti-libcommonrt vti-libdsart vti-libplatformrt; do
    write_ipk "$name" x64
done

bash "$validator" spiderman-build-"$build_number" "$tmp/incoming"

reject() {
    if "$@" >/dev/null 2>&1; then
        echo "Unexpected acceptance: $*" >&2
        exit 1
    fi
}

mv "$tmp/incoming/72-0000-000_vti-libcommonrt_1.2.3.${build_number}_x64.ipk" \
    "$tmp/incoming/72-0000-000_vti-libcommonrt_1.2.3.41_x64.ipk"
reject bash "$validator" spiderman-build-"$build_number" "$tmp/incoming"
mv "$tmp/incoming/72-0000-000_vti-libcommonrt_1.2.3.41_x64.ipk" \
    "$tmp/incoming/72-0000-000_vti-libcommonrt_1.2.3.${build_number}_x64.ipk"

rm "$tmp/incoming/"*commonrt*x64.ipk
reject bash "$validator" spiderman-build-"$build_number" "$tmp/incoming"
write_ipk vti-libcommonrt x64
write_ipk vti-libcommonrt arm
write_ipk vti-libdsart arm
reject bash "$validator" spiderman-build-"$build_number" "$tmp/incoming"
rm "$tmp/incoming/"*commonrt*arm.ipk "$tmp/incoming/"*dsart*arm.ipk

write_ipk vti-libcommonrt arm
write_ipk vti-libdsart arm
write_ipk vti-libplatformrt arm
bash "$validator" spiderman-build-"$build_number" "$tmp/incoming"

mv "$tmp/incoming/"*platformrt*arm.ipk "$tmp/incoming/vti-libunexpected_1.2.3.42_arm.ipk"
reject bash "$validator" spiderman-build-"$build_number" "$tmp/incoming"
echo "Spiderman package validation tests passed."
