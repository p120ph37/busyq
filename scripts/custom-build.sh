#!/bin/sh
# custom-build.sh — Build a busyq binary with configurable applets and embed support
#
# By default, builds a full binary with all applets and embedded-script
# support enabled (but no script embedded).
#
# When --applets or --scan-script is present (including when implied by
# --embed-script), only the scanned and listed applets are included.
# Otherwise all applets are included.
#
# Usage:
#   custom-build.sh [options] > output-binary
#
# Options:
#   --embed-script=FILE  Embed FILE as an overlay script in the output binary
#   --scan-script=FILE   Scan FILE for applet usage (defaults to the
#                        --embed-script value; set to /dev/null to suppress)
#   --no-embed-support   Disable embedded-script support entirely
#                        (mutually exclusive with --embed-script)
#   --applets LIST       Comma-separated applets to include (cumulative)
#   --ssl                Use the SSL variant (includes TLS + CA certs)
#   --raw                Output uncompressed binary (skip UPX + gzip)
#
# Environment:
#   BUSYQ_DEV_DIR   Path to dev files (default: /opt/busyq)

set -eu

BUSYQ_DEV_DIR="${BUSYQ_DEV_DIR:-/opt/busyq}"
EMBED_SCRIPT=""
SCAN_SCRIPT=""
SCAN_SCRIPT_SET=0
NO_EMBED_SUPPORT=0
EXTRA_APPLETS=""
USE_SSL=0
RAW=0

while [ $# -gt 0 ]; do
    case "$1" in
        --embed-script=*) EMBED_SCRIPT="${1#--embed-script=}"; shift ;;
        --embed-script)   EMBED_SCRIPT="$2"; shift 2 ;;
        --scan-script=*)  SCAN_SCRIPT="${1#--scan-script=}"; SCAN_SCRIPT_SET=1; shift ;;
        --scan-script)    SCAN_SCRIPT="$2"; SCAN_SCRIPT_SET=1; shift 2 ;;
        --no-embed-support) NO_EMBED_SUPPORT=1; shift ;;
        --ssl)     USE_SSL=1; shift ;;
        --raw)     RAW=1; shift ;;
        --applets=*) EXTRA_APPLETS="$EXTRA_APPLETS${EXTRA_APPLETS:+,}${1#--applets=}"; shift ;;
        --applets) EXTRA_APPLETS="$EXTRA_APPLETS${EXTRA_APPLETS:+,}$2"; shift 2 ;;
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

# Validate mutual exclusivity
if [ "$NO_EMBED_SUPPORT" = 1 ] && [ -n "$EMBED_SCRIPT" ]; then
    echo "error: --no-embed-support and --embed-script are mutually exclusive" >&2
    exit 1
fi

# Validate embed script exists
if [ -n "$EMBED_SCRIPT" ] && [ ! -f "$EMBED_SCRIPT" ]; then
    echo "error: embed script not found: $EMBED_SCRIPT" >&2
    exit 1
fi

# Imply scan-script from embed-script when not explicitly set
if [ "$SCAN_SCRIPT_SET" = 0 ] && [ -n "$EMBED_SCRIPT" ]; then
    SCAN_SCRIPT="$EMBED_SCRIPT"
    SCAN_SCRIPT_SET=1
fi

# Validate scan script exists (if set and not /dev/null)
if [ "$SCAN_SCRIPT_SET" = 1 ] && [ -n "$SCAN_SCRIPT" ] \
   && [ "$SCAN_SCRIPT" != "/dev/null" ] && [ ! -f "$SCAN_SCRIPT" ]; then
    echo "error: scan script not found: $SCAN_SCRIPT" >&2
    exit 1
fi

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

# Scan script for applet usage
SCANNED_APPLETS=""
if [ "$SCAN_SCRIPT_SET" = 1 ] && [ -n "$SCAN_SCRIPT" ] \
   && [ "$SCAN_SCRIPT" != "/dev/null" ]; then
    if [ -x "$BUSYQ_DEV_DIR/busyq-scan" ]; then
        SCANNED_APPLETS="$("$BUSYQ_DEV_DIR/busyq-scan" --applets "$SCAN_SCRIPT" 2>/dev/null || true)"
    fi
fi

# Determine if custom applets mode is active
# Custom mode when --applets or --scan-script is present (explicitly or implied)
CUSTOM_APPLETS=0
if [ -n "$EXTRA_APPLETS" ] || [ "$SCAN_SCRIPT_SET" = 1 ]; then
    CUSTOM_APPLETS=1
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

# Build compiler flags
APPLET_DEFS=""
if [ "$CUSTOM_APPLETS" = 1 ]; then
    APPLET_DEFS="-DBUSYQ_CUSTOM_APPLETS"
    for applet in $ALL_APPLETS; do
        APPLET_DEFS="$APPLET_DEFS -DAPPLET_${applet}=1"
    done
fi

if [ "$NO_EMBED_SUPPORT" = 0 ]; then
    APPLET_DEFS="$APPLET_DEFS -DBUSYQ_OVERLAY"
fi

if [ "$USE_SSL" = 1 ]; then
    APPLET_DEFS="$APPLET_DEFS -DBUSYQ_SSL -DAPPLET_ssl_client=1"
fi

# Compile and link
OUTPUT="$WORK/busyq"
if [ "$CUSTOM_APPLETS" = 1 ]; then
    echo "Compiling with applets: ${ALL_APPLETS:-(none)}" >&2
else
    echo "Compiling with all applets" >&2
fi
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
if [ -n "$EMBED_SCRIPT" ]; then
    FINAL="$WORK/busyq-final"
    gzip -9c "$EMBED_SCRIPT" > "$WORK/script.gz"
    cat "$OUTPUT" "$WORK/script.gz" > "$FINAL"
    OUTPUT="$FINAL"
fi

# Output to stdout
cat "$OUTPUT"
