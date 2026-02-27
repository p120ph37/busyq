cmake_minimum_required(VERSION 3.20)
project(busyq C)

# busyq - Single-binary bash+curl+jq (+ upstream GNU tools)
#
# This CMakeLists.txt compiles the busyq entry point and applet table,
# then links everything together with the static libraries produced by
# the vcpkg overlay ports (busyq-bash, busyq-curl, busyq-jq, and
# upstream tool ports for phases 1-6).

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
#   phase1-6 tools > curl > nghttp2 > zlib > brotli > zstd > jq > oniguruma >
#   lzo > ncurses > [mbedtls] > system

set(BUSYQ_LINK_LIBS "")

# Bash libraries
find_library(LIB_BASH bash PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_BUILTINS builtins PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_READLINE readline PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_HISTORY history PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_GLOB glob PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_TILDE tilde PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_SH sh PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)

# Phase 1: Coreutils (single-binary multi-call)
find_library(LIB_COREUTILS coreutils PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)

# Phase 2: Text processing
find_library(LIB_GAWK gawk PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_SED sed PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_GREP grep PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_DIFFUTILS diffutils PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_FINDUTILS findutils PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_ED ed PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_PATCH patch PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)

# Phase 3: Archival
find_library(LIB_TAR tar PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_GZIP gzip PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_BZIP2_TOOL bzip2 PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_XZ xz PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_CPIO cpio PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_LZOP lzop PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_ZIP zip PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_UNZIP unzip PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)

# Phase 4: Small standalone tools
find_library(LIB_BC bc PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_LESS less PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_STRINGS strings PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_TIME time PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_BEEP beep PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_DOS2UNIX dos2unix PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_SHARUTILS sharutils PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_TSET tset PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_WHICH which PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)

# Phase 5: Networking
find_library(LIB_WGET wget PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_NC nc PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_PING ping PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_HOSTNAME hostname PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_WHOIS whois PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)

# Phase 6: Process utilities
find_library(LIB_PROCPS procps PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_PSMISC psmisc PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(LIB_LSOF lsof PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)

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

# lzo (compression library for lzop)
find_library(LIB_LZO lzo2 PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)

# ncurses (terminal handling for bash/readline, less, top, pstree)
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

# Phase 1: Coreutils
if(LIB_COREUTILS)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_COREUTILS})
endif()

# Phase 2: Text processing
if(LIB_GAWK)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_GAWK})
endif()
if(LIB_SED)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_SED})
endif()
if(LIB_GREP)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_GREP})
endif()
if(LIB_DIFFUTILS)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_DIFFUTILS})
endif()
if(LIB_FINDUTILS)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_FINDUTILS})
endif()
if(LIB_ED)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_ED})
endif()
if(LIB_PATCH)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_PATCH})
endif()

# Phase 3: Archival
if(LIB_TAR)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_TAR})
endif()
if(LIB_GZIP)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_GZIP})
endif()
if(LIB_BZIP2_TOOL)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_BZIP2_TOOL})
endif()
if(LIB_XZ)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_XZ})
endif()
if(LIB_CPIO)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_CPIO})
endif()
if(LIB_LZOP)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_LZOP})
endif()
if(LIB_ZIP)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_ZIP})
endif()
if(LIB_UNZIP)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_UNZIP})
endif()

# Phase 4: Small standalone tools
if(LIB_BC)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_BC})
endif()
if(LIB_LESS)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_LESS})
endif()
if(LIB_STRINGS)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_STRINGS})
endif()
if(LIB_TIME)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_TIME})
endif()
if(LIB_BEEP)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_BEEP})
endif()
if(LIB_DOS2UNIX)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_DOS2UNIX})
endif()
if(LIB_SHARUTILS)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_SHARUTILS})
endif()
if(LIB_TSET)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_TSET})
endif()
if(LIB_WHICH)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_WHICH})
endif()

# Phase 5: Networking
if(LIB_WGET)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_WGET})
endif()
if(LIB_NC)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_NC})
endif()
if(LIB_PING)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_PING})
endif()
if(LIB_HOSTNAME)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_HOSTNAME})
endif()
if(LIB_WHOIS)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_WHOIS})
endif()

# Phase 6: Process utilities
if(LIB_PROCPS)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_PROCPS})
endif()
if(LIB_PSMISC)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_PSMISC})
endif()
if(LIB_LSOF)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_LSOF})
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

# lzo (for lzop)
if(LIB_LZO)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_LZO})
endif()

# ncurses (after oniguruma, before SSL — readline, less, top depend on ncurses)
if(LIB_NCURSES)
    list(APPEND BUSYQ_LINK_LIBS ${LIB_NCURSES})
endif()

# SSL: mbedtls libraries + ssl_client applet
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
