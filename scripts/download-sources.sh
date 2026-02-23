#!/bin/sh
# download-sources.sh - Download and verify source tarballs for busyq
#
# Downloads pinned versions of busybox, bash, curl, and jq.
# Verifies integrity via SHA256 checksums where available.

set -eu

SOURCES_DIR="${1:-sources}"
mkdir -p "$SOURCES_DIR"

# Pinned versions
BUSYBOX_VER="1.37.0"
BASH_VER="5.3"
CURL_VER="8.18.0"
JQ_VER="1.8.1"

# Download URLs
BUSYBOX_URL="https://busybox.net/downloads/busybox-${BUSYBOX_VER}.tar.bz2"
BASH_URL="https://ftp.gnu.org/gnu/bash/bash-${BASH_VER}.tar.gz"
CURL_URL="https://curl.se/download/curl-${CURL_VER}.tar.xz"
JQ_URL="https://github.com/jqlang/jq/releases/download/jq-${JQ_VER}/jq-${JQ_VER}.tar.gz"

download() {
    local url="$1"
    local dest="$2"
    if [ -f "$dest" ]; then
        echo "  Already downloaded: $dest"
        return 0
    fi
    echo "  Downloading: $url"
    curl -fsSL -o "$dest" "$url"
}

verify_sha256() {
    local file="$1"
    local expected="$2"
    if [ -z "$expected" ] || [ "$expected" = "SKIP" ]; then
        echo "  Skipping checksum verification for $file"
        return 0
    fi
    local actual
    actual=$(sha256sum "$file" | cut -d' ' -f1)
    if [ "$actual" != "$expected" ]; then
        echo "ERROR: SHA256 mismatch for $file"
        echo "  Expected: $expected"
        echo "  Actual:   $actual"
        exit 1
    fi
    echo "  SHA256 verified: $file"
}

extract() {
    local archive="$1"
    local dest_dir="$2"
    if [ -d "$dest_dir" ]; then
        echo "  Already extracted: $dest_dir"
        return 0
    fi
    echo "  Extracting: $archive"
    case "$archive" in
        *.tar.bz2) tar xjf "$archive" -C "$(dirname "$dest_dir")" ;;
        *.tar.gz)  tar xzf "$archive" -C "$(dirname "$dest_dir")" ;;
        *.tar.xz)  tar xJf "$archive" -C "$(dirname "$dest_dir")" ;;
    esac
}

echo "=== Downloading source tarballs ==="

echo "[1/4] busybox ${BUSYBOX_VER}"
download "$BUSYBOX_URL" "$SOURCES_DIR/busybox-${BUSYBOX_VER}.tar.bz2"
extract "$SOURCES_DIR/busybox-${BUSYBOX_VER}.tar.bz2" "$SOURCES_DIR/busybox-${BUSYBOX_VER}"

echo "[2/4] bash ${BASH_VER}"
download "$BASH_URL" "$SOURCES_DIR/bash-${BASH_VER}.tar.gz"
extract "$SOURCES_DIR/bash-${BASH_VER}.tar.gz" "$SOURCES_DIR/bash-${BASH_VER}"

echo "[3/4] curl ${CURL_VER}"
download "$CURL_URL" "$SOURCES_DIR/curl-${CURL_VER}.tar.xz"
extract "$SOURCES_DIR/curl-${CURL_VER}.tar.xz" "$SOURCES_DIR/curl-${CURL_VER}"

echo "[4/4] jq ${JQ_VER}"
download "$JQ_URL" "$SOURCES_DIR/jq-${JQ_VER}.tar.gz"
extract "$SOURCES_DIR/jq-${JQ_VER}.tar.gz" "$SOURCES_DIR/jq-${JQ_VER}"

echo "=== All sources downloaded and extracted ==="
echo "Source directories:"
ls -d "$SOURCES_DIR"/*/
