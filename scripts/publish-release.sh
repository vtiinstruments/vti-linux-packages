#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "Usage: $0 <release-tag> <incoming-dir> <pages-dir>" >&2
    exit 2
fi

tag=$1
incoming=$2
site=$3
repo=${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}
: "${GH_TOKEN:?GH_TOKEN is required}"
signing_key=${VTI_PACKAGE_SIGNING_KEY:?VTI_PACKAGE_SIGNING_KEY is required}
passphrase=${VTI_PACKAGE_SIGNING_PASSPHRASE:?VTI_PACKAGE_SIGNING_PASSPHRASE is required}

if [[ ! $tag =~ ^((v?|libvtex-v)[0-9]+\.[0-9]+\.[0-9]+|spiderman-build-[0-9]+)$ ]]; then
    echo "Invalid release tag: $tag" >&2
    exit 1
fi
for tool in apt-ftparchive createrepo_c dpkg-deb dpkg-scanpackages dpkg-sig gpg gh git rpm rpmsign rpmkeys; do
    command -v "$tool" >/dev/null || {
        echo "Required publishing tool missing: $tool" >&2
        exit 1
    }
done

mapfile -t debs < <(find "$incoming" -maxdepth 1 -type f -name '*.deb' -print | sort)
mapfile -t rpms < <(find "$incoming" -maxdepth 1 -type f -name '*.rpm' -print | sort)
mapfile -t archives < <(find "$incoming" -maxdepth 1 -type f -name '*.tar.gz' -print | sort)
if [[ $tag == spiderman-build-* ]]; then
    bash "$(dirname "$0")/validate-spiderman.sh" "$tag" "$incoming"
elif [[ $tag == libvtex-v* ]]; then
    expected_version="${tag#libvtex-v}-1"
    if [[ ${#debs[@]} -ne 15 || ${#rpms[@]} -ne 15 || ${#archives[@]} -ne 0 ]]; then
        echo "Expected 15 DEBs and 15 RPMs, and no tarballs, for $tag." >&2
        exit 1
    fi
    declare -A expected_debs expected_rpms
    for name in libbreadboard librtdsimulator libcomparator libdmm libmultifunction libscanner libsystem; do
        expected_debs["vti-$name:amd64"]=1
        expected_debs["vti-$name:i386"]=1
    done
    for name in libBreadboard libRTDSimulator libcomparator libdmm libmultifunction libscanner libsystem; do
        expected_rpms["vti-$name:x86_64"]=1
        expected_rpms["vti-$name:i686"]=1
    done
    expected_debs["vti-libvtex-common:all"]=1
    expected_rpms["vti-libvtex-common:noarch"]=1
    for package in "${debs[@]}"; do
        name=$(dpkg-deb -f "$package" Package)
        architecture=$(dpkg-deb -f "$package" Architecture)
        version=$(dpkg-deb -f "$package" Version)
        key="$name:$architecture"
        if [[ $version != "$expected_version" || ${expected_debs[$key]:-} != 1 ]]; then
            echo "Unexpected or duplicate DEB $key ($version): $package" >&2
            exit 1
        fi
        unset 'expected_debs[$key]'
    done
    for package in "${rpms[@]}"; do
        name=$(rpm -qp --qf '%{NAME}' "$package")
        architecture=$(rpm -qp --qf '%{ARCH}' "$package")
        version=$(rpm -qp --qf '%{VERSION}-%{RELEASE}' "$package")
        key="$name:$architecture"
        if [[ $version != "$expected_version" || ${expected_rpms[$key]:-} != 1 ]]; then
            echo "Unexpected or duplicate RPM $key ($version): $package" >&2
            exit 1
        fi
        unset 'expected_rpms[$key]'
    done
    if (( ${#expected_debs[@]} || ${#expected_rpms[@]} )); then
        echo "Missing required libVTEX packages for $tag." >&2
        exit 1
    fi
else
if [[ ${#debs[@]} -ne 2 || ${#rpms[@]} -ne 2 || ${#archives[@]} -ne 1 ]]; then
    echo "Expected two DEBs, two RPMs, and one dual-architecture tarball for $tag." >&2
    exit 1
fi
expected_version="${tag#v}-1"
amd64_deb=0
i386_deb=0
for package in "${debs[@]}"; do
    [[ $(dpkg-deb -f "$package" Version) == "$expected_version" ]] || {
        echo "DEB version does not match release tag $tag: $package" >&2
        exit 1
    }
    case $(dpkg-deb -f "$package" Architecture) in
        amd64)
            if (( amd64_deb )); then echo "Duplicate amd64 DEB: $package" >&2; exit 1; fi
            amd64_deb=1
            ;;
        i386)
            if (( i386_deb )); then echo "Duplicate i386 DEB: $package" >&2; exit 1; fi
            i386_deb=1
            ;;
        *) echo "Unexpected DEB architecture: $package" >&2; exit 1 ;;
    esac
done
x64_rpm=0
x86_rpm=0
for package in "${rpms[@]}"; do
    [[ $(rpm -qp --qf '%{VERSION}-%{RELEASE}' "$package") == "$expected_version" ]] || {
        echo "RPM version does not match release tag $tag: $package" >&2
        exit 1
    }
    case $(rpm -qp --qf '%{ARCH}' "$package") in
        x86_64)
            if (( x64_rpm )); then echo "Duplicate x86_64 RPM: $package" >&2; exit 1; fi
            x64_rpm=1
            ;;
        i686)
            if (( x86_rpm )); then echo "Duplicate i686 RPM: $package" >&2; exit 1; fi
            x86_rpm=1
            ;;
        *) echo "Unexpected RPM architecture: $package" >&2; exit 1 ;;
    esac
done
if (( ! amd64_deb || ! i386_deb || ! x64_rpm || ! x86_rpm )); then
    echo "Release must contain one package for each supported architecture." >&2
    exit 1
fi
fi

export GNUPGHOME="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/vti-signing-${GITHUB_RUN_ID:-local}"
mkdir -m 700 -p "$GNUPGHOME"
cleanup() {
    gpgconf --kill gpg-agent >/dev/null 2>&1 || true
}
trap cleanup EXIT

printf 'allow-preset-passphrase\n' > "$GNUPGHOME/gpg-agent.conf"
gpgconf --launch gpg-agent
printf '%s' "$signing_key" | gpg --batch --import
key_id=$(gpg --batch --with-colons --list-secret-keys | awk -F: '$1 == "sec" { print $5; exit }')
if [[ -z $key_id ]]; then
    echo "The configured signing key contains no secret key." >&2
    exit 1
fi
preset=$(gpgconf --list-dirs libexecdir)/gpg-preset-passphrase
if [[ ! -x $preset ]]; then
    echo "gpg-preset-passphrase was not found at $preset." >&2
    exit 1
fi
while IFS= read -r grip; do
    [[ -n $grip ]] || continue
    printf '%s' "$passphrase" | "$preset" --preset "$grip"
done < <(gpg --batch --with-colons --with-keygrip --list-secret-keys | awk -F: '$1 == "grp" { print $10 }')
unset passphrase signing_key VTI_PACKAGE_SIGNING_PASSPHRASE VTI_PACKAGE_SIGNING_KEY

gh auth setup-git
remote="https://github.com/$repo.git"
git clone --quiet --single-branch --branch gh-pages "$remote" "$site"

git -C "$site" config user.name "github-actions[bot]"
git -C "$site" config user.email "41898282+github-actions[bot]@users.noreply.github.com"
mkdir -p "$site/pool/main" "$site/rpm" \
    "$site/dists/stable/main/binary-amd64" \
    "$site/dists/stable/main/binary-i386"

for package in "${debs[@]}"; do
    if ! dpkg-sig --verify-role builder "$package" >/dev/null 2>&1; then
        dpkg-sig --sign builder -k "$key_id" "$package"
    fi
    dpkg-sig --verify-role builder "$package"
    architecture=$(dpkg-deb -f "$package" Architecture)
    if [[ $tag == spiderman-build-* && $architecture == x86 ]]; then
        echo "Not indexing legacy x86 DEB: $package"
    elif [[ $tag == spiderman-build-* ]]; then
        name=$(dpkg-deb -f "$package" Package)
        version=$(dpkg-deb -f "$package" Version)
        install -m 0644 "$package" "$site/pool/main/${name}_${version}_${architecture}.deb"
    else
        install -m 0644 "$package" "$site/pool/main/"
    fi
done

rpmsign --define "_signature gpg" --define "_gpg_name $key_id" \
    --define "_gpg_path $GNUPGHOME" --addsign "${rpms[@]}"

gpg --batch --armor --export "$key_id" > "$site/public.key"
install -m 0644 "$site/public.key" "$site/RPM-GPG-KEY-VTI"
rpmdb="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/vti-rpmdb-${GITHUB_RUN_ID:-local}"
mkdir -p "$rpmdb"
rpm --dbpath "$rpmdb" --import "$site/RPM-GPG-KEY-VTI"
for package in "${rpms[@]}"; do
    rpmkeys --dbpath "$rpmdb" --checksig --verbose "$package"
    architecture=$(rpm --dbpath "$rpmdb" -qp --qf '%{ARCH}' "$package")
    if [[ $tag == spiderman-build-* && $architecture == x86 ]]; then
        echo "Not indexing legacy x86 RPM: $package"
    else
        install -m 0644 "$package" "$site/rpm/"
    fi
done

for archive in "${archives[@]}"; do
    gpg --batch --yes --local-user "$key_id" --armor --detach-sign \
        --output "$archive.asc" "$archive"
done

install -m 0644 pages/index.html "$site/index.html"
install -m 0644 packaging/apt-ftparchive.conf "$site/apt-ftparchive.conf"
cat > "$site/vti.repo" <<'REPO'
[vti]
name=VTI Instruments Linux Packages
baseurl=https://vtiinstruments.github.io/vti-ppa/rpm/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://vtiinstruments.github.io/vti-ppa/RPM-GPG-KEY-VTI
REPO

cd "$site"
for architecture in amd64 i386; do
    index="dists/stable/main/binary-$architecture/Packages"
    dpkg-scanpackages --arch "$architecture" --multiversion pool/main /dev/null > "$index"
    gzip --no-name --best --stdout "$index" > "$index.gz"
done
apt-ftparchive -c apt-ftparchive.conf release dists/stable > dists/stable/Release
gpg --batch --yes --local-user "$key_id" --armor --clearsign \
    --output dists/stable/InRelease dists/stable/Release
gpg --batch --yes --local-user "$key_id" --armor --detach-sign \
    --output dists/stable/Release.gpg dists/stable/Release

createrepo_c --database --update rpm
gpg --batch --yes --local-user "$key_id" --armor --detach-sign \
    --output rpm/repodata/repomd.xml.asc rpm/repodata/repomd.xml

signed_assets=("${debs[@]}" "${rpms[@]}" "${archives[@]}")
for archive in "${archives[@]}"; do
    signed_assets+=("$archive.asc")
done
gh release upload "$tag" "${signed_assets[@]}" --clobber --repo "$repo"

git add -A
git commit -m "Publish Linux packages for $tag"
git push origin gh-pages
gh release edit "$tag" --draft=false --repo "$repo"
