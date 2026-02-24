# Dockerfile - Multi-stage build for busyq
#
# Builds two variants of the busyq binary (bash+curl+jq+coreutils):
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
# Install all overlay port dependencies (bash, curl-nossl, jq)
RUN vcpkg install

# Build the busyq binary
RUN cmake -B build/none -S . \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUSYQ_SSL=OFF \
    && cmake --build build/none

# Strip and compress
RUN strip --strip-all build/none/busyq \
    && mkdir -p out \
    && cp build/none/busyq out/busyq \
    && upx --best --lzma out/busyq || true

# ---- Build variant 2: with SSL ----
# Generate embedded CA certificates
RUN scripts/generate-certs.sh src

# Install with SSL feature enabled
RUN vcpkg install "busyq[ssl]"

# Build the SSL variant
RUN cmake -B build/ssl -S . \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUSYQ_SSL=ON \
    && cmake --build build/ssl

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
RUN /busyq -c 'echo "bash: ok"' \
    && /busyq -c 'ls /' > /dev/null \
    && /busyq -c 'cat /dev/null' \
    && /busyq -c 'date +%s' > /dev/null \
    && /busyq -c 'jq -n "{test: true}"' \
    && /busyq -c 'curl --version' > /dev/null \
    && /busyq-ssl -c 'curl --version' | grep -qi tls \
    && echo "All smoke tests passed"

# ============================================================
# Stage 3: Extract binaries
# ============================================================
FROM scratch AS output
COPY --from=build /src/out/busyq /busyq
COPY --from=build /src/out/busyq-ssl /busyq-ssl
