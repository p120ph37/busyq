vcpkg_download_distfile(ARCHIVE
    URLS "https://curl.se/download/curl-8.18.0.tar.xz"
    FILENAME "curl-8.18.0.tar.xz"
    SHA512 0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
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
        -DCURL_DISABLE_SSL=ON
    )
endif()

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        ${CURL_OPTIONS}
)

vcpkg_cmake_build()

# Install libcurl
file(GLOB CURL_STATIC_LIB "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel/lib/libcurl.a")
if(NOT CURL_STATIC_LIB)
    file(GLOB CURL_STATIC_LIB "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel/lib/libcurl-d.a")
endif()
file(INSTALL ${CURL_STATIC_LIB} DESTINATION "${CURRENT_PACKAGES_DIR}/lib")

# We also need the curl tool's main() - build it separately
# Compile curl's src/tool_main.c with -Dmain=curl_main
file(GLOB CURL_TOOL_MAIN_SRC "${SOURCE_PATH}/src/tool_main.c")
if(CURL_TOOL_MAIN_SRC)
    # Build a static library containing all the curl tool source files
    # with main renamed to curl_main
    file(GLOB CURL_TOOL_SRCS "${SOURCE_PATH}/src/tool_*.c")
    file(GLOB CURL_TOOL_HDRS "${SOURCE_PATH}/src/tool_*.h")

    set(CURLMAIN_BUILD_DIR "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel-curlmain")
    file(MAKE_DIRECTORY "${CURLMAIN_BUILD_DIR}")

    # Write a CMakeLists.txt for the curl tool as a static library
    file(WRITE "${CURLMAIN_BUILD_DIR}/CMakeLists.txt" "
cmake_minimum_required(VERSION 3.20)
project(curlmain C)
file(GLOB TOOL_SRCS \"${SOURCE_PATH}/src/tool_*.c\")
# Also need slist_wc.c
list(APPEND TOOL_SRCS \"${SOURCE_PATH}/src/slist_wc.c\")
add_library(curlmain STATIC \${TOOL_SRCS})
target_include_directories(curlmain PRIVATE
    \"${SOURCE_PATH}/include\"
    \"${SOURCE_PATH}/lib\"
    \"${SOURCE_PATH}/src\"
    \"${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel/lib\"
    \"${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel/include\"
    \"${CURRENT_INSTALLED_DIR}/include\"
)
target_compile_definitions(curlmain PRIVATE
    HAVE_CONFIG_H
    CURL_STATICLIB
    main=curl_main
)
target_compile_options(curlmain PRIVATE -include \"${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel/lib/curl_config.h\")
")

    vcpkg_execute_required_process(
        COMMAND "${CMAKE_COMMAND}" -S "${CURLMAIN_BUILD_DIR}" -B "${CURLMAIN_BUILD_DIR}/build"
            "-DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}"
        WORKING_DIRECTORY "${CURLMAIN_BUILD_DIR}"
        LOGNAME "curlmain-configure-${TARGET_TRIPLET}"
    )

    vcpkg_execute_required_process(
        COMMAND "${CMAKE_COMMAND}" --build "${CURLMAIN_BUILD_DIR}/build"
        WORKING_DIRECTORY "${CURLMAIN_BUILD_DIR}"
        LOGNAME "curlmain-build-${TARGET_TRIPLET}"
    )

    file(GLOB CURLMAIN_LIB "${CURLMAIN_BUILD_DIR}/build/libcurlmain.a")
    if(CURLMAIN_LIB)
        file(INSTALL ${CURLMAIN_LIB} DESTINATION "${CURRENT_PACKAGES_DIR}/lib")
    endif()
endif()

# Install headers
file(INSTALL "${SOURCE_PATH}/include/curl" DESTINATION "${CURRENT_PACKAGES_DIR}/include")

# Install copyright
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
