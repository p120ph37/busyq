# Dockerfile - Multi-stage build for busyq
#
# Builds two variants of the busyq binary (bash+curl+jq+coreutils):
#   1. busyq      - No SSL (smaller)
#   2. busyq-ssl  - With mbedtls + embedded Mozilla CA bundle
#
# Also produces LTO library artifacts for custom builds:
#   3. libbusyq.a     - No-SSL merged library (LTO bitcode)
#   4. libbusyq-ssl.a - SSL merged library (LTO bitcode)
#   5. busyq-dev/     - Headers + scripts for custom builds
#
# Usage:
#   docker buildx build --output=out .
#
# The output directory will contain binaries, libraries, and dev files.

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
    xz

# Copy project files
COPY . /src
WORKDIR /src

# ---- Build variant 1: no SSL ----
# CMakePresets.json configures the vcpkg toolchain file, which handles
# package installation (via vcpkg.json manifest) during cmake configure.
RUN cmake --preset no-ssl && cmake --build --preset no-ssl

# Strip and compress binaries; also copy library artifact
RUN strip --strip-all build/no-ssl/busyq \
    && mkdir -p out/busyq-dev \
    && cp build/no-ssl/busyq out/busyq \
    && cp build/no-ssl/libbusyq.a out/libbusyq.a \
    && (upx --best --lzma out/busyq || true) \
    && if [ -f build/no-ssl/busyq-scan ]; then \
        strip --strip-all build/no-ssl/busyq-scan \
        && cp build/no-ssl/busyq-scan out/busyq-scan \
        && (upx --best --lzma out/busyq-scan || true); \
    fi

# ---- Build variant 2: with SSL ----
# Generate embedded CA certificates (needed before vcpkg builds curl[ssl])
RUN scripts/generate-certs.sh src

# The "ssl" preset sets VCPKG_MANIFEST_FEATURES=ssl, which tells vcpkg
# to install the ssl feature dependencies (mbedtls, curl[ssl]).
RUN cmake --preset ssl && cmake --build --preset ssl

# Strip and compress binary; also copy library artifact
RUN strip --strip-all build/ssl/busyq \
    && cp build/ssl/busyq out/busyq-ssl \
    && cp build/ssl/libbusyq.a out/libbusyq-ssl.a \
    && (upx --best --lzma out/busyq-ssl || true)

# ---- Copy dev files for custom builds ----
RUN cp src/applet_table.h out/busyq-dev/ \
    && cp src/applets.def out/busyq-dev/ \
    && cp scripts/gen-applet-table.sh out/busyq-dev/ \
    && if [ -f out/busyq-scan ]; then \
        cp out/busyq-scan out/busyq-dev/; \
    fi

# ============================================================
# Stage 2: Smoke tests
# ============================================================
FROM alpine:latest AS test
COPY --from=build /src/out/busyq /busyq
COPY --from=build /src/out/busyq-ssl /busyq-ssl
RUN /busyq -c 'echo "bash: ok"' \
    && /busyq -c 'ls /' > /dev/null \
    && /busyq -c 'cat /dev/null' \
    && /busyq -c 'date +%s' > /dev/null \
    && /busyq -c 'jq -n "{test: true}"' \
    && /busyq -c 'curl --version' > /dev/null \
    && /busyq-ssl -c 'curl --version' | grep -qi tls \
    && echo "All smoke tests passed"

# Smoke test the scanner if built
COPY --from=build /src/out/busyq-scan* /tmp/
RUN if [ -f /tmp/busyq-scan ]; then \
        echo '#!/bin/bash' > /tmp/test.sh \
        && echo 'ls -la /tmp' >> /tmp/test.sh \
        && echo 'curl http://example.com | jq .' >> /tmp/test.sh \
        && /tmp/busyq-scan --raw /tmp/test.sh | grep -q 'CMD' \
        && echo "Scanner smoke test passed"; \
    fi

# ============================================================
# Stage 3: Extract binaries + libraries
# ============================================================
FROM scratch AS output
COPY --from=build /src/out/busyq /busyq
COPY --from=build /src/out/busyq-ssl /busyq-ssl
COPY --from=build /src/out/busyq-scan* /
COPY --from=build /src/out/libbusyq.a /libbusyq.a
COPY --from=build /src/out/libbusyq-ssl.a /libbusyq-ssl.a
COPY --from=build /src/out/busyq-dev/ /busyq-dev/
