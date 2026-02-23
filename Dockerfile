# Dockerfile - Multi-stage build for busyq
#
# Builds two variants of the busyq binary:
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
RUN apk add --no-cache \
    upx \
    ncurses-dev \
    ncurses-static \
    autoconf \
    automake \
    libtool \
    bison \
    flex \
    texinfo \
    perl \
    linux-headers

# Copy project files
COPY . /src
WORKDIR /src

# Install vcpkg library dependencies (mbedtls, oniguruma)
# These are built with LTO flags via EXTRA_CFLAGS automatically
RUN vcpkg install --triplet "$(uname -m)-linux"

# Download and extract source tarballs
RUN scripts/download-sources.sh

# Build variant 1: no SSL
RUN scripts/build.sh --no-ssl

# Build variant 2: with mbedtls SSL + embedded CA certs
RUN scripts/build.sh --with-mbedtls

# ============================================================
# Stage 2: Extract binaries
# ============================================================
FROM scratch AS output
COPY --from=build /src/out/busyq /busyq
COPY --from=build /src/out/busyq-ssl /busyq-ssl
