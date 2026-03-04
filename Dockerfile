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
#   docker buildx build --target test .           # build + smoke tests
#   docker buildx build --target latest --load .   # load SSL image locally
#
# Caching strategy:
#   In CI, BuildKit cache mounts persist the vcpkg binary cache and download
#   directory across builds via the buildkit-cache-dance GitHub Action.  Even
#   when Docker layer cache is invalidated by source changes, vcpkg can skip
#   rebuilding packages whose inputs haven't changed (~45 min savings).
#   Locally, BuildKit persists cache mounts natively within the builder.

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

# Copy project files
COPY . /src
WORKDIR /src

# Validate applets.h sort order (binary search requires lexicographic order)
RUN grep '_BQ_IF(APPLET_' src/applets.h | grep 'APPLET(' | \
    sed 's/.*APPLET([^,]*, //;s/,.*//' > /tmp/applet_cmds.txt \
    && sort -c /tmp/applet_cmds.txt \
    || (echo "ERROR: src/applets.h entries are not sorted by command name" && exit 1)

# ---- Build variant 1: no SSL ----
# Cache mounts: vcpkg binary cache (per-package zip archives keyed by ABI hash)
# and source downloads.  In CI these are persisted via buildkit-cache-dance;
# locally, BuildKit keeps them in the builder instance between builds.
# Cache mount contents are NOT part of the layer -- only the built binaries are.
RUN --mount=type=cache,target=/root/.cache/vcpkg/archives,id=vcpkg-archives,sharing=locked \
    --mount=type=cache,target=/opt/vcpkg/downloads,id=vcpkg-downloads,sharing=locked \
    cmake --preset no-ssl && cmake --build --preset no-ssl

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
RUN --mount=type=cache,target=/root/.cache/vcpkg/archives,id=vcpkg-archives,sharing=locked \
    --mount=type=cache,target=/opt/vcpkg/downloads,id=vcpkg-downloads,sharing=locked \
    cmake --preset ssl && cmake --build --preset ssl

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
    && /busyq -c 'nslookup --help' > /dev/null \
    && /busyq -c 'ip link show lo' > /dev/null \
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
RUN apk add --no-cache clang lld upx gzip
COPY --from=build /src/out/libbusyq.a /opt/busyq/libbusyq.a
COPY --from=build /src/out/libbusyq-nossl.a /opt/busyq/libbusyq-nossl.a
COPY --from=build /src/out/busyq-dev/ /opt/busyq/
COPY scripts/custom-build.sh /usr/local/bin/custom-build
ENTRYPOINT ["custom-build"]

# ---- Custom build smoke tests ----
FROM custom AS custom-test
# Test 1: Manual applets only (no script, no embed)
RUN custom-build --applets ls,cat,date --raw > /tmp/test-binary \
    && chmod +x /tmp/test-binary \
    && /tmp/test-binary -c 'echo "custom build: ok"' \
    && /tmp/test-binary -c 'ls /' > /dev/null \
    && /tmp/test-binary -c 'date +%s' > /dev/null \
    && echo "Custom build test 1 passed: manual applets"
# Test 2: Scan + embed script
RUN printf '#!/bin/bash\necho "EMBED_OK:$0:$1"\nls /\ndate +%%s\n' > /tmp/test.sh \
    && custom-build --embed-script=/tmp/test.sh --raw > /tmp/test-embed \
    && chmod +x /tmp/test-embed \
    && /tmp/test-embed hello | grep -q 'EMBED_OK:/tmp/test-embed:hello' \
    && echo "Custom build test 2 passed: scan + embed"
# Test 3: --no-embed-support disables overlay
RUN custom-build --no-embed-support --applets ls --raw > /tmp/test-noembed \
    && chmod +x /tmp/test-noembed \
    && /tmp/test-noembed -c 'ls /' > /dev/null \
    && echo "Custom build test 3 passed: no embed support"
# Test 4: Multiple --applets (cumulative)
RUN custom-build --applets ls --applets cat --applets date --raw > /tmp/test-multi \
    && chmod +x /tmp/test-multi \
    && /tmp/test-multi -c 'ls /' > /dev/null \
    && /tmp/test-multi -c 'date +%s' > /dev/null \
    && echo "Custom build test 4 passed: cumulative --applets"
# Test 5: --busy preset
RUN custom-build --busy --raw > /tmp/test-busy \
    && chmod +x /tmp/test-busy \
    && /tmp/test-busy -c 'ls /' > /dev/null \
    && /tmp/test-busy -c 'date +%s' > /dev/null \
    && /tmp/test-busy -c 'echo hello | grep hello' \
    && /tmp/test-busy -c 'echo hello | sed s/hello/world/' \
    && /tmp/test-busy -c 'tar --version' > /dev/null \
    && echo "Custom build test 5 passed: --busy preset"
# Test 6: --busy + --net composing presets
RUN custom-build --busy --net --raw > /tmp/test-composed \
    && chmod +x /tmp/test-composed \
    && /tmp/test-composed -c 'curl --version' > /dev/null \
    && /tmp/test-composed -c 'ls /' > /dev/null \
    && echo "Custom build test 6 passed: composed presets"
