cmake_minimum_required(VERSION 3.20)
project(busyq C)

# busyq - Single-binary bash+curl+jq+busybox
#
# This CMakeLists.txt compiles the busyq entry point and applet table,
# then links everything together with the static libraries produced by
# the vcpkg overlay ports (busyq-bash, busyq-busybox, busyq-curl, busyq-jq).

set(CMAKE_C_STANDARD 11)

# Options
option(BUSYQ_SSL "Build with mbedTLS SSL support and embedded certificates" OFF)

# Find libraries installed by our overlay ports
# These are found via CMAKE_PREFIX_PATH set by vcpkg toolchain

# --- busyq source files ---
add_executable(busyq
    src/main.c
    src/applet_table.c
)

target_include_directories(busyq PRIVATE
    src
    ${CMAKE_CURRENT_BINARY_DIR}
)

# vcpkg-installed headers (oniguruma, curl, jq, etc.)
target_include_directories(busyq PRIVATE
    "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/include"
)

# --- Link order matters for static libraries ---
# bash depends on readline, which depends on ncurses
# The overall link order: bash > builtins > readline > history > glob > tilde > sh >
#   busybox > curl > nghttp2 > zlib > brotli > zstd > jq > oniguruma > ncurses > [mbedtls] > system

set(BUSYQ_LINK_LIBS "")

# Bash libraries
find_library(LIB_BASH bash PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_BUILTINS builtins PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_READLINE readline PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_HISTORY history PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_GLOB glob PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_TILDE tilde PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_SH sh PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)

# Busybox
find_library(LIB_BUSYBOX busybox PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)

# Curl (library + tool main)
find_library(LIB_CURL curl PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_CURLMAIN curlmain PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)

# Curl dependencies (compression + HTTP/2)
find_library(LIB_NGHTTP2 nghttp2 PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_Z z PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_BROTLIDEC brotlidec PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_BROTLICOMMON brotlicommon PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_ZSTD zstd PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)

# jq (library + tool main)
find_library(LIB_JQ jq PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_JQMAIN jqmain PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)

# Oniguruma (regex library for jq)
find_library(LIB_ONIG onig PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)

# ncurses (terminal handling for bash/readline, built via vcpkg for LTO)
find_library(LIB_NCURSES ncursesw PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
if(NOT LIB_NCURSES)
    find_library(LIB_NCURSES ncurses PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
endif()

# Assemble link list
# Bash
if(LIB_BASH)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_BASH})
endif()
if(LIB_BUILTINS)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_BUILTINS})
endif()
if(LIB_READLINE)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_READLINE})
endif()
if(LIB_HISTORY)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_HISTORY})
endif()
if(LIB_GLOB)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_GLOB})
endif()
if(LIB_TILDE)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_TILDE})
endif()
if(LIB_SH)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_SH})
endif()

# Busybox
if(LIB_BUSYBOX)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_BUSYBOX})
endif()

# Curl
if(LIB_CURLMAIN)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_CURLMAIN})
endif()
if(LIB_CURL)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_CURL})
endif()

# Curl dependencies (compression + HTTP/2, linked after curl)
if(LIB_NGHTTP2)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_NGHTTP2})
endif()
if(LIB_Z)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_Z})
endif()
if(LIB_BROTLIDEC)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_BROTLIDEC})
endif()
if(LIB_BROTLICOMMON)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_BROTLICOMMON})
endif()
if(LIB_ZSTD)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_ZSTD})
endif()

# jq
if(LIB_JQMAIN)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_JQMAIN})
endif()
if(LIB_JQ)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_JQ})
endif()

# Oniguruma
if(LIB_ONIG)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_ONIG})
endif()

# ncurses (after oniguruma, before SSL — readline depends on ncurses)
if(LIB_NCURSES)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_NCURSES})
endif()

# SSL: mbedtls libraries + ssl_client applet (shared TLS for curl and busybox)
if(BUSYQ_SSL)
    target_sources(busyq PRIVATE src/ssl_client_mbedtls.c)
    target_compile_definitions(busyq PRIVATE BUSYQ_SSL)
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/src/embedded_certs.h")
        target_compile_definitions(busyq PRIVATE BUSYQ_EMBEDDED_CERTS)
    endif()

    find_library(LIB_MBEDTLS mbedtls PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
    find_library(LIB_MBEDX509 mbedx509 PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
    find_library(LIB_MBEDCRYPTO mbedcrypto PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
    if(LIB_MBEDTLS)
        list(APPEND BUSYQ_LINK_LIBS ${LIB_MBEDTLS})
    endif()
    if(LIB_MBEDX509)
        list(APPEND BUSYQ_LINK_LIBS ${LIB_MBEDX509})
    endif()
    if(LIB_MBEDCRYPTO)
        list(APPEND BUSYQ_LINK_LIBS ${LIB_MBEDCRYPTO})
    endif()
endif()

# System libraries (musl libc — already LTO-enabled in alpine-clang-vcpkg)
list(APPEND BUSYQ_LINK_LIBS
    m
    dl
    pthread
)

target_link_libraries(busyq PRIVATE ${BUSYQ_LINK_LIBS})

# Static linking
target_link_options(busyq PRIVATE -static -Wl,--gc-sections)

# Install
install(TARGETS busyq RUNTIME DESTINATION bin)
