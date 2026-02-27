# Dockerfile - Multi-stage build for busyq
#
# Builds two variants of the busyq binary (bash+curl+jq+coreutils+tools):
#   1. busyq      - No SSL (smaller)
#   2. busyq-ssl  - With mbedtls + embedded Mozilla CA bundle
#
# Usage:
#   docker buildx build --output=out .
#
# The output directory will contain both binaries.

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

# Strip and compress
RUN strip --strip-all build/no-ssl/busyq \
    && mkdir -p out \
    && cp build/no-ssl/busyq out/busyq \
    && upx --best --lzma out/busyq || true

# ---- Build variant 2: with SSL ----
# Generate embedded CA certificates (needed before vcpkg builds curl[ssl])
RUN scripts/generate-certs.sh src

# The "ssl" preset sets VCPKG_MANIFEST_FEATURES=ssl, which tells vcpkg
# to install the ssl feature dependencies (mbedtls, curl[ssl]).
RUN cmake --preset ssl && cmake --build --preset ssl

# Strip and compress
RUN strip --strip-all build/ssl/busyq \
    && cp build/ssl/busyq out/busyq-ssl \
    && upx --best --lzma out/busyq-ssl || true

# ============================================================
# Stage 2: Smoke tests
# ============================================================
FROM alpine:latest AS test
COPY --from=build /src/out/busyq /busyq
COPY --from=build /src/out/busyq-ssl /busyq-ssl
# Core (Phase 0-1)
RUN /busyq -c 'echo "bash: ok"' \
    && /busyq -c 'ls /' > /dev/null \
    && /busyq -c 'cat /dev/null' \
    && /busyq -c 'date +%s' > /dev/null \
    && /busyq -c 'jq -n "{test: true}"' \
    && /busyq -c 'curl --version' > /dev/null \
    && /busyq-ssl -c 'curl --version' | grep -qi tls \
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
    && /busyq -c 'which ls' > /dev/null \
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

# ============================================================
# Stage 3: Extract binaries
# ============================================================
FROM scratch AS output
COPY --from=build /src/out/busyq /busyq
COPY --from=build /src/out/busyq-ssl /busyq-ssl
