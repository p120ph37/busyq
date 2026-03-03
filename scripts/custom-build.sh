#!/bin/sh
# custom-build.sh — Build a minimal busyq binary from a bash script
#
# Reads a bash script from stdin (or skips scanning with --no-script),
# determines which applets are needed, compiles a custom features.c
# against the pre-built libbusyq.a, applies UPX compression, and
# writes the final binary to stdout.
#
# Usage:
#   custom-build.sh [options] < script.sh > output-binary
#
# Options:
#   --embed       Embed the script as an overlay in the output binary
#   --ssl         Use the SSL variant (includes TLS + CA certs)
#   --applets L   Comma-separated list of additional applets to include
#   --no-script   Don't read/scan a script (use with --applets)
#   --raw         Output uncompressed binary (skip UPX + gzip)
#
# Environment:
#   BUSYQ_DEV_DIR   Path to dev files (default: /opt/busyq)

set -eu

BUSYQ_DEV_DIR="${BUSYQ_DEV_DIR:-/opt/busyq}"
EMBED=0
USE_SSL=0
EXTRA_APPLETS=""
NO_SCRIPT=0
RAW=0

while [ $# -gt 0 ]; do
    case "$1" in
        --embed)   EMBED=1; shift ;;
        --ssl)     USE_SSL=1; shift ;;
        --raw)     RAW=1; shift ;;
        --no-script) NO_SCRIPT=1; shift ;;
        --applets) EXTRA_APPLETS="$2"; shift 2 ;;
        --help|-h)
            sed -n '2,/^$/s/^# //p' "$0"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Select library variant
if [ "$USE_SSL" = 1 ]; then
    LIB="$BUSYQ_DEV_DIR/libbusyq.a"
else
    LIB="$BUSYQ_DEV_DIR/libbusyq-nossl.a"
fi

if [ ! -f "$LIB" ]; then
    echo "error: library not found: $LIB" >&2
    exit 1
fi

# Read script from stdin if not --no-script
SCRIPT_FILE=""
SCANNED_APPLETS=""
if [ "$NO_SCRIPT" = 0 ]; then
    SCRIPT_FILE="$WORK/input.sh"
    cat > "$SCRIPT_FILE"

    if [ ! -s "$SCRIPT_FILE" ]; then
        echo "error: empty script on stdin (use --no-script for manual builds)" >&2
        exit 1
    fi

    # Scan the script for applet usage
    if [ -x "$BUSYQ_DEV_DIR/busyq-scan" ]; then
        SCANNED_APPLETS="$("$BUSYQ_DEV_DIR/busyq-scan" --applets "$SCRIPT_FILE" 2>/dev/null || true)"
    fi
fi

# Merge scanned + extra applets, deduplicate
ALL_APPLETS=""
for a in $(echo "$SCANNED_APPLETS" | tr ',' ' ') $(echo "$EXTRA_APPLETS" | tr ',' ' '); do
    case " $ALL_APPLETS " in
        *" $a "*) ;;  # skip duplicate
        *) ALL_APPLETS="$ALL_APPLETS $a" ;;
    esac
done
ALL_APPLETS="$(echo "$ALL_APPLETS" | sed 's/^ //')"

if [ -z "$ALL_APPLETS" ] && [ "$NO_SCRIPT" = 1 ]; then
    echo "error: --no-script requires --applets" >&2
    exit 1
fi

# Build compiler flags for applet selection
APPLET_DEFS="-DBUSYQ_CUSTOM_APPLETS"
if [ "$EMBED" = 1 ]; then
    APPLET_DEFS="$APPLET_DEFS -DBUSYQ_OVERLAY"
fi
if [ "$USE_SSL" = 1 ]; then
    APPLET_DEFS="$APPLET_DEFS -DBUSYQ_SSL -DAPPLET_ssl_client=1"
fi

for applet in $ALL_APPLETS; do
    APPLET_DEFS="$APPLET_DEFS -DAPPLET_${applet}=1"
done

# Compile and link
OUTPUT="$WORK/busyq"
echo "Compiling with applets: $ALL_APPLETS" >&2
# shellcheck disable=SC2086
clang -fuse-ld=lld $APPLET_DEFS \
    -flto -static -Os \
    "$BUSYQ_DEV_DIR/features.c" \
    -I"$BUSYQ_DEV_DIR" \
    "$LIB" \
    -lm -ldl -lpthread \
    -o "$OUTPUT"

strip --strip-all "$OUTPUT"

# UPX compress
if [ "$RAW" = 0 ] && command -v upx >/dev/null 2>&1; then
    upx --best --lzma "$OUTPUT" >/dev/null 2>&1 || true
fi

# Embed script overlay if requested
if [ "$EMBED" = 1 ] && [ -n "$SCRIPT_FILE" ]; then
    FINAL="$WORK/busyq-final"
    gzip -9c "$SCRIPT_FILE" > "$WORK/script.gz"
    cat "$OUTPUT" "$WORK/script.gz" > "$FINAL"
    OUTPUT="$FINAL"
fi

# Output to stdout
cat "$OUTPUT"
