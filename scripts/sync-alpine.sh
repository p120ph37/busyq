#!/bin/bash
# scripts/sync-alpine.sh - Sync patches and source metadata from Alpine aports
#
# Usage:
#   scripts/sync-alpine.sh <aports-dir> [port-name...]
#
# Example:
#   git clone --depth=1 --branch=3.23-stable https://git.alpinelinux.org/aports /tmp/aports
#   scripts/sync-alpine.sh /tmp/aports
#   scripts/sync-alpine.sh /tmp/aports busyq-sharutils busyq-time
#
# For each port, generates:
#   ports/<port>/alpine-source[-(subdir)].cmake  - Version, URL, SHA512, patch list
#   ports/<port>/patches[/(subdir)]/*.patch       - Patch files from Alpine

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Port mapping: busyq port -> space-separated "aports_path[:subdir]" entries.
# If :subdir is given, patches go into patches/<subdir>/ and the cmake file
# is named alpine-source-<subdir>.cmake. This supports multi-source ports
# like zip (which has separate zip and unzip upstream packages).
declare -A PORT_MAP
PORT_MAP[busyq-sharutils]="main/sharutils"
PORT_MAP[busyq-time]="community/time"
PORT_MAP[busyq-zip]="main/zip:zip main/unzip:unzip"
PORT_MAP[busyq-procps]="main/procps-ng"
PORT_MAP[busyq-psmisc]="main/psmisc"

usage() {
    echo "Usage: $0 <aports-dir> [port-name...]"
    echo
    echo "Syncs Alpine patches and source metadata into vcpkg port directories."
    echo
    echo "Available ports:"
    for port in "${!PORT_MAP[@]}"; do
        echo "  $port -> ${PORT_MAP[$port]}"
    done | sort
    exit 1
}

# Sync a single Alpine package into a busyq port directory.
#
# Arguments:
#   $1 - aports directory (git clone root)
#   $2 - busyq port name (e.g., busyq-sharutils)
#   $3 - aports path (e.g., main/sharutils)
#   $4 - subdir (optional, e.g., "zip" or "unzip")
sync_package() {
    local aports_dir="$1"
    local port_name="$2"
    local aports_path="$3"
    local subdir="${4:-}"

    local apkbuild="$aports_dir/$aports_path/APKBUILD"
    if [[ ! -f "$apkbuild" ]]; then
        echo "  ERROR: APKBUILD not found: $apkbuild" >&2
        return 1
    fi

    local port_dir="$PROJECT_DIR/ports/$port_name"
    local patches_dir="$port_dir/patches${subdir:+/$subdir}"
    local cmake_file="$port_dir/alpine-source${subdir:+-$subdir}.cmake"

    echo "  Syncing $aports_path -> $port_name${subdir:+ ($subdir)}"

    # Source the APKBUILD in a subshell to extract variables.
    # We stub out all lifecycle functions so only variable assignments execute.
    local vars
    vars=$(
        # Stub lifecycle functions
        prepare() { :; }; build() { :; }; check() { :; }; package() { :; }
        default_prepare() { :; }; update_config_sub() { :; }
        amove() { :; }
        # Stub any subpackage functions (e.g., libproc2())
        libproc2() { :; }
        # Provide empty build-time variables
        CBUILD="" CHOST="" CARCH="" CFLAGS="" CPPFLAGS="" LDFLAGS=""
        srcdir="" pkgdir="" startdir=""

        # shellcheck disable=SC1090
        . "$apkbuild"

        # Emit variables in a parseable format
        printf 'PKGNAME=%q\n' "$pkgname"
        printf 'PKGVER=%q\n' "$pkgver"
        printf 'PKGREL=%q\n' "$pkgrel"

        # Source entries (URLs and patch filenames)
        local idx=0
        for s in $source; do
            printf 'SRC_%d=%q\n' "$idx" "$s"
            idx=$((idx + 1))
        done
        printf 'SRC_COUNT=%d\n' "$idx"

        # SHA512 entries (alternating hash + filename)
        idx=0
        for s in $sha512sums; do
            printf 'SUM_%d=%q\n' "$idx" "$s"
            idx=$((idx + 1))
        done
        printf 'SUM_COUNT=%d\n' "$idx"
    )

    # Import the parsed variables into this shell
    eval "$vars"

    # First source entry is the tarball
    local tarball_entry="$SRC_0"
    local tarball_url tarball_filename

    # Handle "filename::url" syntax used by some APKBUILDs
    if [[ "$tarball_entry" == *"::"* ]]; then
        tarball_filename="${tarball_entry%%::*}"
        tarball_url="${tarball_entry#*::}"
    else
        tarball_url="$tarball_entry"
        tarball_filename="${tarball_url##*/}"
    fi

    # First SHA512 entry is the tarball hash (SUM_0=hash, SUM_1=filename)
    local tarball_sha512="$SUM_0"

    # Collect patch filenames (remaining source entries ending in .patch*)
    local -a patch_names=()
    for ((i = 1; i < SRC_COUNT; i++)); do
        local src_var="SRC_${i}"
        local entry="${!src_var}"
        case "$entry" in
            *.patch|*.patch.gz|*.patch.xz)
                patch_names+=("$entry")
                ;;
        esac
    done

    # Create patches directory (clear old Alpine patches)
    mkdir -p "$patches_dir"
    # Only remove .patch files, preserve any busyq-specific files
    rm -f "$patches_dir"/*.patch "$patches_dir"/*.patch.gz "$patches_dir"/*.patch.xz 2>/dev/null || true

    # Copy patch files from the aports directory
    local copied=0
    for patch in "${patch_names[@]}"; do
        local patch_src="$aports_dir/$aports_path/$patch"
        if [[ -f "$patch_src" ]]; then
            cp "$patch_src" "$patches_dir/"
            echo "    + $patch"
            copied=$((copied + 1))
        else
            echo "    WARNING: patch not found: $patch_src" >&2
        fi
    done
    echo "    ${copied} patches copied"

    # Generate alpine-source cmake file
    {
        echo "# Auto-generated by scripts/sync-alpine.sh"
        echo "# Source: Alpine Linux aports ($aports_path)"
        echo "# Package: ${PKGNAME} ${PKGVER}-r${PKGREL}"
        echo "# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo ""
        echo "set(ALPINE_PKGNAME \"${PKGNAME}\")"
        echo "set(ALPINE_PKGVER \"${PKGVER}\")"
        echo ""
        echo "set(ALPINE_SOURCE_URLS"
        echo "    \"${tarball_url}\""
        echo ")"
        echo "set(ALPINE_SOURCE_FILENAME \"${tarball_filename}\")"
        echo "set(ALPINE_SOURCE_SHA512 ${tarball_sha512})"
        echo ""
        if [[ ${#patch_names[@]} -gt 0 ]]; then
            echo "set(ALPINE_PATCHES"
            for patch in "${patch_names[@]}"; do
                echo "    ${patch}"
            done
            echo ")"
        else
            echo "set(ALPINE_PATCHES)"
        fi
    } > "$cmake_file"

    echo "    Generated: $(basename "$cmake_file")"
}

# ── Main ──────────────────────────────────────────────────────────────────────

if [[ $# -lt 1 ]]; then
    usage
fi

APORTS_DIR="$1"
shift

if [[ ! -d "$APORTS_DIR" ]]; then
    echo "ERROR: aports directory not found: $APORTS_DIR" >&2
    exit 1
fi

# Determine which ports to sync
declare -a PORTS
if [[ $# -gt 0 ]]; then
    PORTS=("$@")
else
    # Sort for deterministic output
    mapfile -t PORTS < <(printf '%s\n' "${!PORT_MAP[@]}" | sort)
fi

# Show branch info from the aports clone
BRANCH=$(cd "$APORTS_DIR" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
COMMIT=$(cd "$APORTS_DIR" && git rev-parse --short HEAD 2>/dev/null || echo "unknown")

echo "Alpine aports sync"
echo "  Branch: $BRANCH"
echo "  Commit: $COMMIT"
echo ""

for port in "${PORTS[@]}"; do
    if [[ -z "${PORT_MAP[$port]:-}" ]]; then
        echo "WARNING: Unknown port '$port' (skipping)" >&2
        echo ""
        continue
    fi

    echo "Port: $port"

    # Process each aports_path[:subdir] mapping
    for mapping in ${PORT_MAP[$port]}; do
        aports_path="${mapping%%:*}"
        subdir=""
        if [[ "$mapping" == *":"* ]]; then
            subdir="${mapping#*:}"
        fi
        sync_package "$APORTS_DIR" "$port" "$aports_path" "$subdir"
    done
    echo ""
done

echo "Sync complete."
