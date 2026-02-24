vcpkg_download_distfile(ARCHIVE
    URLS "https://curl.se/download/curl-8.18.0.tar.xz"
    FILENAME "curl-8.18.0.tar.xz"
    SHA512 50c7a7b0528e0019697b0c59b3e56abb2578c71d77e4c085b56797276094b5611718c0a9cb2b14db7f8ab502fcf8f42a364297a3387fae3870a4d281484ba21c
)

# SSL patches are guarded by #ifdef BUSYQ_EMBEDDED_CERTS / USE_MBEDTLS,
# so they're safe to apply unconditionally.
if("ssl" IN_LIST FEATURES)
    set(SSL_PATCHES
        embedded-certs.patch
        extra-certs-envvar.patch
    )
else()
    set(SSL_PATCHES "")
endif()

vcpkg_extract_source_archive(SOURCE_PATH ARCHIVE "${ARCHIVE}"
    PATCHES ${SSL_PATCHES}
)

# Build curl with CMake (curl has native CMake support)
# Match Alpine's curl feature set (minus LDAP, libssh2, HTTP/3).
# Protocols: Alpine enables all except LDAP.
# Libraries: zlib, brotli, zstd, nghttp2 added to match Alpine.
# Not matched: HTTP/3+QUIC (needs OpenSSL), c-ares, libidn2, libpsl.
set(CURL_OPTIONS
    -DBUILD_CURL_EXE=OFF
    -DBUILD_SHARED_LIBS=OFF
    -DBUILD_STATIC_LIBS=ON
    -DBUILD_TESTING=OFF
    -DCURL_DISABLE_LDAP=ON
    -DENABLE_MANUAL=OFF
    -DENABLE_UNIX_SOCKETS=ON
    -DENABLE_IPV6=ON
    -DENABLE_WEBSOCKETS=ON
    -DHTTP_ONLY=OFF
    -DCURL_USE_LIBPSL=OFF
    -DCURL_USE_LIBSSH2=OFF
    -DCURL_ZLIB=ON
    -DCURL_BROTLI=ON
    -DCURL_ZSTD=ON
    -DUSE_NGHTTP2=ON
    -DUSE_LIBIDN2=OFF
)

if("ssl" IN_LIST FEATURES)
    # Add embedded certs flags via VCPKG_C_FLAGS so they compose with
    # toolchain flags (LTO, -Oz, etc.) instead of overriding them.
    set(BUSYQ_SRC_DIR "${CURRENT_PORT_DIR}/../../src")
    string(APPEND VCPKG_C_FLAGS " -DBUSYQ_EMBEDDED_CERTS -I${BUSYQ_SRC_DIR}")
    string(APPEND VCPKG_CXX_FLAGS " -DBUSYQ_EMBEDDED_CERTS -I${BUSYQ_SRC_DIR}")
    list(APPEND CURL_OPTIONS
        -DCURL_USE_MBEDTLS=ON
        -DCURL_USE_OPENSSL=OFF
    )
else()
    list(APPEND CURL_OPTIONS
        -DCURL_USE_OPENSSL=OFF
        -DCURL_USE_MBEDTLS=OFF
        -DCURL_USE_WOLFSSL=OFF
        -DCURL_USE_GNUTLS=OFF
        -DCURL_USE_BEARSSL=OFF
        -DCURL_USE_RUSTLS=OFF
        -DCURL_DISABLE_SSL=ON
    )
endif()

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        ${CURL_OPTIONS}
    MAYBE_UNUSED_VARIABLES
        CURL_DISABLE_SSL
        CURL_USE_BEARSSL
        ENABLE_MANUAL
        ENABLE_WEBSOCKETS
)

# Save curl_config.h (generated during cmake configure) to a stable location
# before vcpkg_cmake_build() runs, because newer vcpkg cleans build tree artifacts
# after the build+install step completes.
set(CURLMAIN_BUILD_DIR "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel-curlmain")
file(MAKE_DIRECTORY "${CURLMAIN_BUILD_DIR}")
file(COPY
    "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel/lib/curl_config.h"
    DESTINATION "${CURLMAIN_BUILD_DIR}"
)

vcpkg_cmake_build()
vcpkg_cmake_install()

# Install libcurl from packages dir (vcpkg_cmake_install puts it there)
# Also handle case where it didn't install automatically
if(NOT EXISTS "${CURRENT_PACKAGES_DIR}/lib/libcurl.a")
    file(GLOB CURL_STATIC_LIB
        "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel/lib/libcurl.a"
        "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel/lib/libcurl-d.a"
    )
    if(CURL_STATIC_LIB)
        file(INSTALL ${CURL_STATIC_LIB} DESTINATION "${CURRENT_PACKAGES_DIR}/lib")
    endif()
endif()

# Detect toolchain flags so the ad-hoc curlmain compilation gets LTO, -Oz, etc.
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

set(CURLMAIN_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(CURLMAIN_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

# Build curl tool source files with -Dmain=curl_main into libcurlmain.a
# We compile them via shell since CMAKE_C_COMPILER is not set in portfile context.
# curl_config.h was saved to CURLMAIN_BUILD_DIR before the build tree was cleaned.

# Write a build script for curl tool objects to avoid quoting issues in sh -c.
# Only tool_main.c gets -Dmain=curl_main; other files are compiled normally.
file(WRITE "${CURLMAIN_BUILD_DIR}/build_curlmain.sh" "\
#!/bin/sh
set -eu
SRCDIR=\"${SOURCE_PATH}/src\"
CC=\"${CURLMAIN_CC}\"
TOOLCHAIN_CFLAGS=\"${CURLMAIN_CFLAGS}\"
BASE_CFLAGS=\"-DHAVE_CONFIG_H -DCURL_STATICLIB\"
INCS=\"-include ${CURLMAIN_BUILD_DIR}/curl_config.h -I${SOURCE_PATH}/include -I${SOURCE_PATH}/lib -I${SOURCE_PATH}/src -I${CURLMAIN_BUILD_DIR} -I${CURRENT_INSTALLED_DIR}/include\"
for f in \"\$SRCDIR\"/*.c \"\$SRCDIR\"/toolx/*.c; do
    [ -f \"\$f\" ] || continue
    bn=\$(basename \"\$f\" .c)
    EXTRA=\"\"
    if [ \"\$bn\" = \"tool_main\" ]; then
        EXTRA=\"-Dmain=curl_main\"
    fi
    \$CC \$TOOLCHAIN_CFLAGS \$BASE_CFLAGS \$EXTRA \$INCS -c \"\$f\" -o \"\${bn}.o\" || exit 1
done
ar rcs \"${CURRENT_PACKAGES_DIR}/lib/libcurlmain.a\" *.o
")

vcpkg_execute_required_process(
    COMMAND sh "${CURLMAIN_BUILD_DIR}/build_curlmain.sh"
    WORKING_DIRECTORY "${CURLMAIN_BUILD_DIR}"
    LOGNAME "curlmain-build-${TARGET_TRIPLET}"
)

# Install headers
file(INSTALL "${SOURCE_PATH}/include/curl" DESTINATION "${CURRENT_PACKAGES_DIR}/include")

# Clean up extra files vcpkg_cmake_install may have placed
file(REMOVE_RECURSE
    "${CURRENT_PACKAGES_DIR}/debug"
    "${CURRENT_PACKAGES_DIR}/bin"
    "${CURRENT_PACKAGES_DIR}/lib/cmake"
    "${CURRENT_PACKAGES_DIR}/lib/pkgconfig"
)

# Install copyright
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
