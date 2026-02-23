vcpkg_download_distfile(ARCHIVE
    URLS "https://curl.se/download/curl-8.18.0.tar.xz"
    FILENAME "curl-8.18.0.tar.xz"
    SHA512 50c7a7b0528e0019697b0c59b3e56abb2578c71d77e4c085b56797276094b5611718c0a9cb2b14db7f8ab502fcf8f42a364297a3387fae3870a4d281484ba21c
)

vcpkg_extract_source_archive(SOURCE_PATH ARCHIVE "${ARCHIVE}")

# Apply patches for SSL variant
if("ssl" IN_LIST FEATURES)
    vcpkg_apply_patches(
        SOURCE_PATH "${SOURCE_PATH}"
        PATCHES
            embedded-certs.patch
            extra-certs-envvar.patch
    )
endif()

# Build curl with CMake (curl has native CMake support)
set(CURL_OPTIONS
    -DBUILD_CURL_EXE=OFF
    -DBUILD_SHARED_LIBS=OFF
    -DBUILD_STATIC_LIBS=ON
    -DBUILD_TESTING=OFF
    -DCURL_DISABLE_DICT=ON
    -DCURL_DISABLE_FTP=ON
    -DCURL_DISABLE_IMAP=ON
    -DCURL_DISABLE_LDAP=ON
    -DCURL_DISABLE_MQTT=ON
    -DCURL_DISABLE_POP3=ON
    -DCURL_DISABLE_RTSP=ON
    -DCURL_DISABLE_SMB=ON
    -DCURL_DISABLE_SMTP=ON
    -DCURL_DISABLE_TELNET=ON
    -DCURL_DISABLE_TFTP=ON
    -DCURL_DISABLE_GOPHER=ON
    -DCURL_DISABLE_NTLM=ON
    -DENABLE_MANUAL=OFF
    -DENABLE_UNIX_SOCKETS=ON
    -DENABLE_IPV6=ON
    -DHTTP_ONLY=OFF
    -DCURL_USE_LIBPSL=OFF
    -DCURL_USE_LIBSSH2=OFF
    -DCURL_ZLIB=OFF
    -DCURL_BROTLI=OFF
    -DCURL_ZSTD=OFF
    -DUSE_NGHTTP2=OFF
    -DUSE_LIBIDN2=OFF
)

if("ssl" IN_LIST FEATURES)
    # The embedded_certs.h is generated into the project's src/ directory
    set(BUSYQ_SRC_DIR "${CURRENT_PORT_DIR}/../../src")
    list(APPEND CURL_OPTIONS
        -DCURL_USE_MBEDTLS=ON
        -DCURL_USE_OPENSSL=OFF
        "-DCMAKE_C_FLAGS=-DBUSYQ_EMBEDDED_CERTS -I${BUSYQ_SRC_DIR}"
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
)

vcpkg_cmake_build()

# Install libcurl
file(GLOB CURL_STATIC_LIB "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel/lib/libcurl.a")
if(NOT CURL_STATIC_LIB)
    file(GLOB CURL_STATIC_LIB "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel/lib/libcurl-d.a")
endif()
file(INSTALL ${CURL_STATIC_LIB} DESTINATION "${CURRENT_PACKAGES_DIR}/lib")

# Build curl tool source files with -Dmain=curl_main into libcurlmain.a
# We compile them via shell since CMAKE_C_COMPILER is not set in portfile context
set(CURLMAIN_BUILD_DIR "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel-curlmain")
file(MAKE_DIRECTORY "${CURLMAIN_BUILD_DIR}")

set(CURL_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

# Compile all tool_*.c and slist_wc.c with main renamed to curl_main
vcpkg_execute_required_process(
    COMMAND sh -c "cd '${CURLMAIN_BUILD_DIR}' && for f in '${SOURCE_PATH}'/src/tool_*.c '${SOURCE_PATH}'/src/slist_wc.c; do [ -f \"$f\" ] && cc -Dmain=curl_main -DHAVE_CONFIG_H -DCURL_STATICLIB -include '${CURL_BUILD_REL}/lib/curl_config.h' -I'${SOURCE_PATH}/include' -I'${SOURCE_PATH}/lib' -I'${SOURCE_PATH}/src' -I'${CURL_BUILD_REL}/lib' -I'${CURL_BUILD_REL}/include' -I'${CURRENT_INSTALLED_DIR}/include' -c \"$f\" -o \"$(basename $f .c).o\" || exit 1; done && ar rcs '${CURRENT_PACKAGES_DIR}/lib/libcurlmain.a' *.o"
    WORKING_DIRECTORY "${CURLMAIN_BUILD_DIR}"
    LOGNAME "curlmain-build-${TARGET_TRIPLET}"
)

# Install headers
file(INSTALL "${SOURCE_PATH}/include/curl" DESTINATION "${CURRENT_PACKAGES_DIR}/include")

# Install copyright
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
