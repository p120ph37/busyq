# Dockerfile - Multi-stage build for busyq
#
# Builds two variants of the busyq binary (bash+curl+jq+coreutils+tools):
#   1. busyq        - With mbedtls + embedded Mozilla CA bundle (default)
#   2. busyq-nossl  - No SSL (smaller)
#
# Also produces LTO library artifacts for custom builds:
#   3. libbusyq.a       - SSL merged library (LTO bitcode)
#   4. libbusyq-nossl.a - No-SSL merged library (LTO bitcode)
#   5. busyq-dev/       - Headers + scripts for custom builds
#
# Usage:
#   docker buildx build --output=out .
#
# The output directory will contain binaries, libraries, and dev files.
#
# Caching strategy:
#   The build stage uses a two-phase COPY to enable Docker layer caching
#   for vcpkg package installation.  Phase 1 copies only the package
#   manifest (vcpkg.json, ports/, CMakeLists.txt) and runs cmake configure
#   to trigger vcpkg install.  Phase 2 copies the real source files and
#   builds.  Since vcpkg_installed/ is in .dockerignore, pre-installed
#   packages survive the Phase 2 COPY and vcpkg install becomes a no-op.
#   This avoids ~15 min of package rebuilds when only source files change.

# ============================================================
# Stage 1: Build environment
# ============================================================
FROM p120ph37/alpine-clang-vcpkg:latest AS build

# LTO flags propagate through vcpkg dependency builds via the
# EXTRA_* mechanism provided by alpine-clang-vcpkg
ENV EXTRA_CFLAGS="-flto -ffunction-sections -fdata-sections -Oz"
ENV EXTRA_CXXFLAGS="-flto -ffunction-sections -fdata-sections -Oz"
ENV EXTRA_LDFLAGS="-flto -Wl,--gc-sections -Wl,--icf=all"
ENV EXTRA_CFLAGS_RELEASE="-Oz -DNDEBUG"

# Install additional build dependencies not in the base image
# NOTE: ncurses is built via vcpkg (not apk) so it gets LTO like everything else
RUN apk add --no-cache \
    upx \
    autoconf \
    automake \
    libtool \
    bison \
    flex \
    texinfo \
    perl \
    linux-headers \
    xz \
    ed \
    patch \
    gettext-dev

# ---- Phase 1: Pre-install vcpkg packages (cached until ports/manifest change) ----
# Copy build system + package manifest files.  Overlay ports reference
# scripts/cmake/ helpers and a few source files (features.h is needed by
# the bash port; busyq_scan_walk.c + busyq_scan.h are compiled during bash build).
COPY vcpkg.json vcpkg-configuration.json CMakePresets.json CMakeLists.txt /src/
COPY ports/ /src/ports/
COPY scripts/cmake/ /src/scripts/cmake/
COPY src/features.h src/busyq_scan_walk.c src/busyq_scan.h /src/src/
WORKDIR /src

# Create source stubs for files cmake needs to see at configure time
# but that are NOT needed by vcpkg port builds.
RUN touch src/main.c src/features.c src/overlay.c \
          src/busyq_scan_main.c src/ssl_client_mbedtls.c \
          src/applets.h src/overlay.h

# Configure no-ssl preset: triggers vcpkg to install all base packages.
# This layer is cached as long as the files above haven't changed,
# saving ~15 minutes of package compilation on each run.
RUN cmake --preset no-ssl

# ---- Phase 2: Build with real sources ----
# vcpkg_installed/ and build/ are in .dockerignore, so pre-installed
# packages and cmake cache from Phase 1 survive this COPY.
COPY . /src

# Validate applets.h sort order (binary search requires lexicographic order)
RUN grep '_BQ_IF(APPLET_' src/applets.h | grep 'APPLET(' | \
    sed 's/.*APPLET([^,]*, //;s/,.*//' > /tmp/applet_cmds.txt \
    && sort -c /tmp/applet_cmds.txt \
    || (echo "ERROR: src/applets.h entries are not sorted by command name" && exit 1)

# ---- Build variant 1: no SSL ----
# cmake reconfigures with real sources; vcpkg install is a no-op
# (base packages already installed from Phase 1).
RUN cmake --preset no-ssl && cmake --build --preset no-ssl

# Strip and compress binaries; also copy library artifact (keep a pre-UPX copy for overlay tests)
RUN strip --strip-all build/no-ssl/busyq \
    && mkdir -p out/busyq-dev \
    && cp build/no-ssl/busyq out/busyq-nopack \
    && cp build/no-ssl/busyq out/busyq-nossl \
    && cp build/no-ssl/libbusyq.a out/libbusyq-nossl.a \
    && (upx --best --lzma out/busyq-nossl || true) \
    && strip --strip-all build/no-ssl/busyq-scan \
    && cp build/no-ssl/busyq-scan out/busyq-scan \
    && (upx --best --lzma out/busyq-scan || true)

# ---- Build variant 2: with SSL ----
# Generate embedded CA certificates (needed before vcpkg builds curl[ssl])
RUN scripts/generate-certs.sh src

# The "ssl" preset sets VCPKG_MANIFEST_FEATURES=ssl, which tells vcpkg
# to install the ssl feature dependencies (mbedtls, curl[ssl]).
RUN cmake --preset ssl && cmake --build --preset ssl \
    || { echo "=== SSL build failed, dumping vcpkg logs ===" >&2; \
         for f in /opt/vcpkg/buildtrees/busyq-curl/curlmain-build-*-err.log \
                  /opt/vcpkg/buildtrees/busyq-curl/*-rel-curlmain/build_curlmain.sh \
                  /opt/vcpkg/buildtrees/busyq-curl/*-rel/lib/curl_config.h; do \
             [ -f "$f" ] && echo "--- $f ---" >&2 && cat "$f" >&2; \
         done; false; }

# Strip and compress binary; also copy library artifact
RUN strip --strip-all build/ssl/busyq \
    && cp build/ssl/busyq out/busyq \
    && cp build/ssl/libbusyq.a out/libbusyq.a \
    && (upx --best --lzma out/busyq || true)

# ---- Copy dev files for custom builds ----
RUN cp src/features.h out/busyq-dev/ \
    && cp src/applets.h out/busyq-dev/ \
    && cp src/features.c out/busyq-dev/ \
    && cp src/overlay.h out/busyq-dev/ \
    && cp out/busyq-scan out/busyq-dev/

# ============================================================
# Stage 2: Smoke tests
# ============================================================
FROM alpine:latest AS test
COPY --from=build /src/out/busyq /busyq
COPY --from=build /src/out/busyq-nopack /busyq-nopack
COPY --from=build /src/out/busyq-nossl /busyq-nossl
# Core (Phase 0-1)
RUN /busyq -c 'echo "bash: ok"' \
    && /busyq -c 'ls /' > /dev/null \
    && /busyq -c 'cat /dev/null' \
    && /busyq -c 'date +%s' > /dev/null \
    && /busyq -c 'jq -n "{test: true}"' \
    && /busyq -c 'curl --version' > /dev/null \
    && /busyq -c 'curl --version' | grep -qi tls \
    && echo "Core tests passed"
# Phase 2: Text processing
RUN /busyq -c 'echo hello | awk "{print \$1}"' \
    && /busyq -c 'echo hello | sed s/hello/world/' \
    && /busyq -c 'echo hello | grep hello' \
    && /busyq -c 'echo -e "a\nb" | diff - <(echo -e "a\nc") || true' \
    && /busyq -c 'find / -maxdepth 1 -name "busyq" -print' > /dev/null \
    && /busyq -c 'echo test | xargs echo' \
    && echo "Phase 2 tests passed"
# Phase 3: Archival
RUN /busyq -c 'echo test | gzip | gunzip' \
    && /busyq -c 'echo test | bzip2 | bunzip2' \
    && /busyq -c 'echo test | xz | unxz' \
    && /busyq -c 'tar --version' > /dev/null \
    && echo "Phase 3 tests passed"
# Phase 4: Small standalone tools
RUN /busyq -c 'echo "1+1" | bc' \
    && /busyq -c 'type ls' > /dev/null \
    && /busyq -c 'strings /busyq | head -1' > /dev/null \
    && echo "Phase 4 tests passed"
# Phase 5: Networking
RUN /busyq -c 'hostname' > /dev/null \
    && echo "Phase 5 tests passed"
# Phase 6: Process utilities
RUN /busyq -c 'ps aux' > /dev/null \
    && /busyq -c 'free' > /dev/null \
    && echo "Phase 6 tests passed"
RUN echo "All smoke tests passed"

# Smoke test the scanner
COPY --from=build /src/out/busyq-scan /tmp/busyq-scan
RUN echo '#!/bin/bash' > /tmp/test.sh \
    && echo 'ls -la /tmp' >> /tmp/test.sh \
    && echo 'curl http://example.com | jq .' >> /tmp/test.sh \
    && /tmp/busyq-scan --raw /tmp/test.sh | grep -q 'CMD' \
    && echo "Scanner smoke test passed"

# Overlay tests: 2x2 matrix of binary (stripped / UPX) × script (raw / gzip)
# UPX metadata after ELF segments is auto-detected and skipped.
RUN set -e \
    && printf 'echo "BUSYQ_OVERLAY:$0:args=$#:${1-}:${2-}"\n' > /tmp/test.sh \
    && gzip -9c /tmp/test.sh > /tmp/test.sh.gz \
    && cat /busyq-nopack /tmp/test.sh > /tmp/t1 && chmod +x /tmp/t1 \
    && /tmp/t1 hello world | grep -q 'BUSYQ_OVERLAY:/tmp/t1:args=2:hello:world' \
    && echo "overlay 1/4 passed: stripped + raw" \
    && cat /busyq-nopack /tmp/test.sh.gz > /tmp/t2 && chmod +x /tmp/t2 \
    && /tmp/t2 hello world | grep -q 'BUSYQ_OVERLAY:/tmp/t2:args=2:hello:world' \
    && echo "overlay 2/4 passed: stripped + gzip" \
    && cat /busyq-nossl /tmp/test.sh > /tmp/t3 && chmod +x /tmp/t3 \
    && /tmp/t3 hello world | grep -q 'BUSYQ_OVERLAY:/tmp/t3:args=2:hello:world' \
    && echo "overlay 3/4 passed: upx + raw" \
    && cat /busyq-nossl /tmp/test.sh.gz > /tmp/t4 && chmod +x /tmp/t4 \
    && /tmp/t4 hello world | grep -q 'BUSYQ_OVERLAY:/tmp/t4:args=2:hello:world' \
    && echo "overlay 4/4 passed: upx + gzip" \
    && echo "All overlay tests passed"

# ============================================================
# Stage 3: Publishable images
# ============================================================

# ---- busyq:latest (SSL variant, from scratch) ----
FROM scratch AS latest
COPY --from=build /src/out/busyq /busyq
RUN ["/busyq", "-c", "mkdir -p /bin && ln -sf /busyq /bin/busyq"]

# ---- busyq:nossl (no-SSL variant, from scratch) ----
FROM scratch AS nossl
COPY --from=build /src/out/busyq-nossl /busyq
RUN ["/busyq", "-c", "mkdir -p /bin && ln -sf /busyq /bin/busyq"]

# ---- busyq:custom (Alpine-based build environment) ----
FROM alpine:3.23 AS custom
RUN apk add --no-cache clang lld musl-dev upx gzip
COPY --from=build /src/out/libbusyq.a /opt/busyq/libbusyq.a
COPY --from=build /src/out/libbusyq-nossl.a /opt/busyq/libbusyq-nossl.a
COPY --from=build /src/out/busyq-dev/ /opt/busyq/
COPY scripts/custom-build.sh /usr/local/bin/custom-build
ENTRYPOINT ["custom-build"]

# ---- Custom build smoke test ----
FROM custom AS custom-test
RUN printf '#!/bin/bash\nls /tmp\necho hello | cat\ndate +%%s\n' > /tmp/test.sh \
    && custom-build --applets ls,cat,date --no-script --raw > /tmp/test-binary \
    && chmod +x /tmp/test-binary \
    && /tmp/test-binary -c 'echo "custom build: ok"' \
    && /tmp/test-binary -c 'ls /' > /dev/null \
    && /tmp/test-binary -c 'date +%s' > /dev/null \
    && echo "Custom build smoke test passed"

# ============================================================
# Stage 4: Extract binaries + libraries (local builds)
# ============================================================
FROM scratch AS output
COPY --from=build /src/out/busyq /busyq
COPY --from=build /src/out/busyq-nossl /busyq-nossl
COPY --from=build /src/out/busyq-scan /busyq-scan
COPY --from=build /src/out/libbusyq.a /libbusyq.a
COPY --from=build /src/out/libbusyq-nossl.a /libbusyq-nossl.a
COPY --from=build /src/out/busyq-dev/ /busyq-dev/
