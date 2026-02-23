#!/bin/sh
# build.sh - LEGACY build orchestration for busyq
#
# DEPRECATED: This script is superseded by the vcpkg overlay ports build.
# The new build uses: vcpkg install && cmake -B build && cmake --build build
# See ports/ directory and the Dockerfile for the current build approach.
#
# Builds all components and links them into a single static binary.
#
# Usage:
#   scripts/build.sh --no-ssl        # Build without SSL
#   scripts/build.sh --with-mbedtls  # Build with mbedtls SSL + embedded certs

set -eu

# ---- Configuration ----
SSL_MODE="none"
case "${1:-}" in
    --no-ssl)      SSL_MODE="none" ;;
    --with-mbedtls) SSL_MODE="mbedtls" ;;
    *) echo "Usage: $0 [--no-ssl|--with-mbedtls]"; exit 1 ;;
esac

NPROC=$(nproc 2>/dev/null || echo 4)
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCES_DIR="$PROJECT_DIR/sources"
BUILD_DIR="$PROJECT_DIR/build/${SSL_MODE}"
OUT_DIR="$PROJECT_DIR/out"

# Versions (must match download-sources.sh)
BUSYBOX_VER="1.37.0"
BASH_VER="5.3"
CURL_VER="8.18.0"
JQ_VER="1.8.1"

# Source directories
BB_SRC="$SOURCES_DIR/busybox-${BUSYBOX_VER}"
BASH_SRC="$SOURCES_DIR/bash-${BASH_VER}"
CURL_SRC="$SOURCES_DIR/curl-${CURL_VER}"
JQ_SRC="$SOURCES_DIR/jq-${JQ_VER}"

# Compile flags (no LTO for now to keep configure tests working)
LTO_CFLAGS="-ffunction-sections -fdata-sections -Oz -DNDEBUG"
LTO_LDFLAGS="-Wl,--gc-sections -static"

# vcpkg installed dir (set by alpine-clang-vcpkg environment)
VCPKG_INSTALLED="${VCPKG_INSTALLED_DIR:-$(ls -d /src/vcpkg_installed/*-linux 2>/dev/null | head -1)}"

mkdir -p "$BUILD_DIR" "$OUT_DIR"

echo "=== Building busyq (SSL: $SSL_MODE) ==="

# ---- Step 1: Apply patches ----
apply_patches() {
    local src_dir="$1"
    local patch_dir="$2"
    if [ -d "$patch_dir" ] && [ -f "$src_dir/.busyq_patched" ]; then
        echo "  Patches already applied to $src_dir"
        return 0
    fi
    if [ -d "$patch_dir" ]; then
        echo "  Applying patches from $patch_dir to $src_dir"
        for p in "$patch_dir"/*.patch; do
            [ -f "$p" ] || continue
            echo "    Applying: $(basename "$p")"
            patch -d "$src_dir" -p1 < "$p" || true
        done
        touch "$src_dir/.busyq_patched"
    fi
}

echo "[1/7] Applying patches..."
apply_patches "$BB_SRC" "$PROJECT_DIR/patches/busybox"
apply_patches "$BASH_SRC" "$PROJECT_DIR/patches/bash"
apply_patches "$CURL_SRC" "$PROJECT_DIR/patches/curl"
apply_patches "$JQ_SRC" "$PROJECT_DIR/patches/jq"

# ---- Step 2: Build jq as static library ----
echo "[2/7] Building jq..."
JQ_BUILD="$BUILD_DIR/jq"
if [ ! -f "$JQ_BUILD/src/.libs/libjq.a" ]; then
    mkdir -p "$JQ_BUILD"
    cd "$JQ_SRC"
    if [ ! -f configure ]; then
        autoreconf -i
    fi
    cd "$JQ_BUILD"
    "$JQ_SRC/configure" \
        CC=clang \
        CFLAGS="$LTO_CFLAGS -Dmain=jq_main" \
        LDFLAGS="$LTO_LDFLAGS" \
        --enable-static \
        --disable-shared \
        --disable-maintainer-mode \
        --with-oniguruma="$VCPKG_INSTALLED" \
        --prefix="$BUILD_DIR/install"
    make -j"$NPROC"
fi
echo "  jq built: $JQ_BUILD/src/.libs/libjq.a"

# ---- Step 3: Build curl as static library ----
echo "[3/7] Building curl..."
CURL_BUILD="$BUILD_DIR/curl"
if [ ! -f "$CURL_BUILD/lib/.libs/libcurl.a" ]; then
    mkdir -p "$CURL_BUILD"
    cd "$CURL_SRC"
    if [ ! -f configure ]; then
        autoreconf -i
    fi

    CURL_SSL_FLAGS=""
    CURL_EXTRA_CFLAGS=""
    if [ "$SSL_MODE" = "mbedtls" ]; then
        CURL_SSL_FLAGS="--with-mbedtls=$VCPKG_INSTALLED"
        CURL_EXTRA_CFLAGS="-DBUSYQ_EMBEDDED_CERTS -I$PROJECT_DIR/src"
    else
        CURL_SSL_FLAGS="--without-ssl"
    fi

    cd "$CURL_BUILD"
    "$CURL_SRC/configure" \
        CC=clang \
        CFLAGS="$LTO_CFLAGS -Dmain=curl_main $CURL_EXTRA_CFLAGS" \
        LDFLAGS="$LTO_LDFLAGS" \
        --enable-static \
        --disable-shared \
        --disable-dict \
        --disable-ftp \
        --disable-imap \
        --disable-ldap \
        --disable-mqtt \
        --disable-pop3 \
        --disable-rtsp \
        --disable-smb \
        --disable-smtp \
        --disable-telnet \
        --disable-tftp \
        --disable-gopher \
        --disable-manual \
        --disable-docs \
        --disable-ntlm \
        --enable-ipv6 \
        --enable-unix-sockets \
        $CURL_SSL_FLAGS \
        --prefix="$BUILD_DIR/install"
    make -j"$NPROC"
fi
echo "  curl built: $CURL_BUILD/lib/.libs/libcurl.a"

# ---- Step 4: Build bash as static library ----
echo "[4/7] Building bash..."
BASH_BUILD="$BUILD_DIR/bash"
if [ ! -f "$BASH_BUILD/libbash.a" ] && [ ! -f "$BASH_BUILD/bash" ]; then
    mkdir -p "$BASH_BUILD"
    cd "$BASH_BUILD"

    # Copy applet headers into bash source for the patches to find
    cp "$PROJECT_DIR/src/applet_table.h" "$BASH_SRC/busyq_applet_table.h"

    "$BASH_SRC/configure" \
        CC=clang \
        CFLAGS="$LTO_CFLAGS -I$PROJECT_DIR/src" \
        LDFLAGS="$LTO_LDFLAGS" \
        --enable-static-link \
        --without-bash-malloc \
        --disable-nls \
        --host="$(uname -m)-linux-musl" \
        --prefix="$BUILD_DIR/install"
    make -j"$NPROC"
fi
echo "  bash built"

# ---- Step 5: Build busybox ----
echo "[5/7] Building busybox..."
BB_BUILD="$BUILD_DIR/busybox"
if [ ! -f "$BB_BUILD/busybox_unstripped" ]; then
    mkdir -p "$BB_BUILD"
    cp "$PROJECT_DIR/config/busybox.config" "$BB_BUILD/.config"
    cd "$BB_BUILD"

    # Point to busybox source
    make -C "$BB_SRC" O="$BB_BUILD" \
        CC=clang \
        CFLAGS="$LTO_CFLAGS -include $PROJECT_DIR/src/bb_namespace.h -DBUSYQ_NO_BUSYBOX_MAIN" \
        LDFLAGS="$LTO_LDFLAGS" \
        BUSYQ_SRC_DIR="$PROJECT_DIR/src" \
        -j"$NPROC" \
        busybox_unstripped
fi
echo "  busybox built"

# ---- Step 6: Generate busybox applet table header ----
echo "[6/7] Generating applet table and linking..."

# Generate busybox_applets.h from the build
if [ -f "$PROJECT_DIR/patches/busybox/003-applet-table-export.patch" ]; then
    sh "$BB_SRC/scripts/gen_busyq_applets.sh" "$BB_BUILD" "$PROJECT_DIR/src/busybox_applets.h" 2>/dev/null || {
        # Fallback: generate a minimal applet table from the config
        echo "  Generating applet table from config..."
        echo "/* Auto-generated - minimal fallback */" > "$PROJECT_DIR/src/busybox_applets.h"
    }
fi

# If SSL variant, generate embedded certs
if [ "$SSL_MODE" = "mbedtls" ]; then
    echo "  Generating embedded CA certificates..."
    "$PROJECT_DIR/scripts/generate-certs.sh" "$PROJECT_DIR/src"
fi

# ---- Step 7: Final link ----
echo "[7/7] Final link..."

# Compile our entry point and applet table
clang $LTO_CFLAGS -I"$PROJECT_DIR/src" \
    -c "$PROJECT_DIR/src/main.c" -o "$BUILD_DIR/main.o"
clang $LTO_CFLAGS -I"$PROJECT_DIR/src" \
    -c "$PROJECT_DIR/src/applet_table.c" -o "$BUILD_DIR/applet_table.o"

# Determine output binary name
if [ "$SSL_MODE" = "mbedtls" ]; then
    OUT_BIN="$OUT_DIR/busyq-ssl"
else
    OUT_BIN="$OUT_DIR/busyq"
fi

# Link everything together
LINK_LIBS=""
LINK_LIBS="$LINK_LIBS $BUILD_DIR/main.o $BUILD_DIR/applet_table.o"

# Bash libraries
LINK_LIBS="$LINK_LIBS -L$BASH_BUILD -L$BASH_BUILD/builtins -L$BASH_BUILD/lib/readline -L$BASH_BUILD/lib/glob -L$BASH_BUILD/lib/tilde -L$BASH_BUILD/lib/sh"
LINK_LIBS="$LINK_LIBS -lbash -lbuiltins -lreadline -lhistory -lglob -ltilde -lsh"

# Busybox
LINK_LIBS="$LINK_LIBS -L$BB_BUILD -lbusybox"

# curl
LINK_LIBS="$LINK_LIBS -L$CURL_BUILD/lib/.libs -lcurl"

# jq
LINK_LIBS="$LINK_LIBS -L$JQ_BUILD/src/.libs -ljq"

# vcpkg-installed libraries
LINK_LIBS="$LINK_LIBS -L$VCPKG_INSTALLED/lib -lonig"

# SSL libraries (mbedtls variant only)
if [ "$SSL_MODE" = "mbedtls" ]; then
    LINK_LIBS="$LINK_LIBS -lmbedtls -lmbedx509 -lmbedcrypto"
fi

# System libraries
LINK_LIBS="$LINK_LIBS -lncursesw -lm -ldl -lpthread"

clang $LTO_LDFLAGS $LINK_LIBS -o "$OUT_BIN"

echo "  Linked: $OUT_BIN"

# Strip
strip --strip-all "$OUT_BIN"
echo "  Stripped: $(stat -c%s "$OUT_BIN") bytes"

# UPX compress
if command -v upx >/dev/null 2>&1; then
    upx --best --lzma "$OUT_BIN"
    echo "  UPX compressed: $(stat -c%s "$OUT_BIN") bytes"
else
    echo "  WARNING: upx not found, skipping compression"
fi

echo "=== Build complete: $OUT_BIN ==="
ls -lh "$OUT_BIN"
