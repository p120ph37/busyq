cmake_minimum_required(VERSION 3.20)
project(busyq C)

# busyq - Single-binary bash+curl+jq (+ upstream GNU tools)
#
# This CMakeLists.txt does two things:
#
# 1. Produces libbusyq.a — a merged static archive (LLVM LTO bitcode)
#    containing the entry point (main.c) plus all component libraries
#    (bash, coreutils, curl, jq, etc.), but NOT the applet dispatch
#    table.  This library is the artifact for custom builds.
#
# 2. Produces the busyq binary — libbusyq.a linked with an applet
#    table (full or filtered).  The applet table is the only piece
#    that varies between a full build and a minimal custom build.
#
# Custom build workflow:
#   1. Build libbusyq.a once (expensive: vcpkg ports + LTO compilation)
#   2. Run:  busyq-scan myscript.sh --applets
#   3. Compile: cc -DBUSYQ_CUSTOM_APPLETS -DAPPLET_curl=1 -DAPPLET_ls=1 \
#               -flto -static -Os src/applets.c -Isrc/ libbusyq.a \
#               -lm -ldl -lpthread -o busyq
#      (Fast: no vcpkg rebuild, just compile one .c + final link w/ LTO)

set(CMAKE_C_STANDARD 11)

# Options
option(BUSYQ_SSL "Build with mbedTLS SSL support and embedded certificates" OFF)
set(BUSYQ_APPLETS "" CACHE STRING
    "Semicolon-separated applet names to include (empty string = all)")

# =====================================================================
# Find and collect component libraries from overlay ports
#
# Each component is found via find_library and appended to
# BUSYQ_COMPONENT_LIBS.  All components end up in one merged archive
# (libbusyq.a via MRI script), so ordering here is for readability.
# =====================================================================
set(_LIB_DIR "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib")
set(BUSYQ_COMPONENT_LIBS "")

# Helper: find a library and append to component list if found
macro(_busyq_find _var _name)
    find_library(${_var} ${_name} PATHS "${_LIB_DIR}" NO_DEFAULT_PATH)
    if(${_var})
        list(APPEND BUSYQ_COMPONENT_LIBS ${${_var}})
    endif()
endmacro()

# Bash
_busyq_find(LIB_BASH       bash)
_busyq_find(LIB_BUILTINS   builtins)
_busyq_find(LIB_READLINE   readline)
_busyq_find(LIB_HISTORY    history)
_busyq_find(LIB_GLOB       glob)
_busyq_find(LIB_TILDE      tilde)
_busyq_find(LIB_SH         sh)

# Coreutils
_busyq_find(LIB_COREUTILS  coreutils)

# Text processing
_busyq_find(LIB_GAWK       gawk)
_busyq_find(LIB_SED        sed)
_busyq_find(LIB_GREP       grep)
_busyq_find(LIB_DIFFUTILS  diffutils)
_busyq_find(LIB_FINDUTILS  findutils)
_busyq_find(LIB_ED         ed)
_busyq_find(LIB_PATCH      patch)

# Archival
_busyq_find(LIB_TAR        tar)
_busyq_find(LIB_GZIP       gzip)
_busyq_find(LIB_BZIP2_TOOL bzip2)
_busyq_find(LIB_XZ         xz)
_busyq_find(LIB_CPIO       cpio)
_busyq_find(LIB_LZOP       lzop)
_busyq_find(LIB_ZIP        zip)
_busyq_find(LIB_UNZIP      unzip)

# Small standalone tools
_busyq_find(LIB_BC         bc)
_busyq_find(LIB_LESS       less)
_busyq_find(LIB_STRINGS    strings)
_busyq_find(LIB_TIME       time)
_busyq_find(LIB_DOS2UNIX   dos2unix)
_busyq_find(LIB_SHARUTILS  sharutils)
_busyq_find(LIB_TSET       tset)
_busyq_find(LIB_WHICH      which)

# Networking
_busyq_find(LIB_WGET       wget)
_busyq_find(LIB_NC         nc)
_busyq_find(LIB_PING       ping)
_busyq_find(LIB_HOSTNAME   hostname)
_busyq_find(LIB_WHOIS      whois)

# Process utilities
_busyq_find(LIB_PROCPS     procps)
_busyq_find(LIB_PSMISC     psmisc)
_busyq_find(LIB_LSOF       lsof)

# Curl + dependencies
_busyq_find(LIB_CURLMAIN   curlmain)
_busyq_find(LIB_CURL       curl)
_busyq_find(LIB_NGHTTP2    nghttp2)
_busyq_find(LIB_Z          z)
_busyq_find(LIB_BROTLIDEC  brotlidec)
_busyq_find(LIB_BROTLICOMMON brotlicommon)
_busyq_find(LIB_ZSTD       zstd)

# jq + dependencies
_busyq_find(LIB_JQMAIN     jqmain)
_busyq_find(LIB_JQ         jq)
_busyq_find(LIB_ONIG       onig)

# Shared dependencies
_busyq_find(LIB_LZO        lzo2)

# ncurses (try wide-char variant first)
find_library(LIB_NCURSES ncursesw PATHS "${_LIB_DIR}" NO_DEFAULT_PATH)
if(NOT LIB_NCURSES)
    find_library(LIB_NCURSES ncurses PATHS "${_LIB_DIR}" NO_DEFAULT_PATH)
endif()
if(LIB_NCURSES)
    list(APPEND BUSYQ_COMPONENT_LIBS ${LIB_NCURSES})
endif()

# SSL (conditional)
if(BUSYQ_SSL)
    _busyq_find(LIB_MBEDTLS    mbedtls)
    _busyq_find(LIB_MBEDX509   mbedx509)
    _busyq_find(LIB_MBEDCRYPTO mbedcrypto)
endif()

# =====================================================================
# main.o — compiled as an object library so it can go into both
# the merged libbusyq.a and the final executable
# =====================================================================
add_library(busyq_main OBJECT src/main.c)
target_include_directories(busyq_main PRIVATE
    src
    ${CMAKE_CURRENT_BINARY_DIR}
    "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/include"
)

# SSL sources are part of the library (not the applet table)
if(BUSYQ_SSL)
    target_sources(busyq_main PRIVATE src/ssl_client_mbedtls.c)
    target_compile_definitions(busyq_main PRIVATE BUSYQ_SSL)
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/src/embedded_certs.h")
        target_compile_definitions(busyq_main PRIVATE BUSYQ_EMBEDDED_CERTS)
    endif()
endif()

# =====================================================================
# libbusyq.a — merged archive of main.o + all component libraries
#
# Contains everything needed for a busyq binary EXCEPT the applet
# dispatch table (applets.c).  Distributed as an LTO-enabled
# artifact so users can link a custom applet table quickly:
#
#   cc -DBUSYQ_CUSTOM_APPLETS -DAPPLET_curl=1 -flto -static \
#      src/applets.c -Isrc/ libbusyq.a -lm -ldl -lpthread -o busyq
#
# Uses an ar MRI script to merge all archives + object files into one.
# =====================================================================
set(BUSYQ_LIB "${CMAKE_CURRENT_BINARY_DIR}/libbusyq.a")
set(BUSYQ_MRI "${CMAKE_CURRENT_BINARY_DIR}/libbusyq.mri")

# Generate the MRI script at configure time
set(_mri_content "create ${BUSYQ_LIB}\n")
string(APPEND _mri_content "addmod $<JOIN:$<TARGET_OBJECTS:busyq_main>,\naddmod >\n")
foreach(_lib ${BUSYQ_COMPONENT_LIBS})
    string(APPEND _mri_content "addlib ${_lib}\n")
endforeach()
string(APPEND _mri_content "save\nend\n")
file(GENERATE OUTPUT "${BUSYQ_MRI}" CONTENT "${_mri_content}")

add_custom_command(
    OUTPUT "${BUSYQ_LIB}"
    COMMAND ${CMAKE_AR} -M < "${BUSYQ_MRI}"
    DEPENDS busyq_main "${BUSYQ_MRI}" ${BUSYQ_COMPONENT_LIBS}
    COMMENT "Merging component libraries into libbusyq.a"
    VERBATIM
)
add_custom_target(busyq-lib DEPENDS "${BUSYQ_LIB}")

# =====================================================================
# Applet table — full or filtered via preprocessor
#
# src/applets.c includes src/applets.h (X-macro registry).  Filtering
# is done at compile time: -DBUSYQ_CUSTOM_APPLETS plus individual
# -DAPPLET_<name>=1 flags select which applets to include.  No code
# generation step is needed.
#
# When BUSYQ_APPLETS is set (semicolon-separated list), CMake converts
# it to the appropriate compile definitions.
# =====================================================================
add_executable(busyq src/applets.c)

target_include_directories(busyq PRIVATE
    src
    ${CMAKE_CURRENT_BINARY_DIR}
    "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/include"
)

if(BUSYQ_SSL)
    target_compile_definitions(busyq PRIVATE BUSYQ_SSL)
endif()

if(BUSYQ_APPLETS)
    target_compile_definitions(busyq PRIVATE BUSYQ_CUSTOM_APPLETS)
    foreach(_applet ${BUSYQ_APPLETS})
        target_compile_definitions(busyq PRIVATE "APPLET_${_applet}=1")
    endforeach()
    message(STATUS "busyq: custom applet build — ${BUSYQ_APPLETS}")
endif()

# Link against the merged library
target_link_libraries(busyq PRIVATE "${BUSYQ_LIB}" m dl pthread)
add_dependencies(busyq busyq-lib)

# Static linking
target_link_options(busyq PRIVATE -static -Wl,--gc-sections)

# =====================================================================
# busyq-scan — AST-walking script scanner
#
# A separate binary that uses bash's parser (in -n mode) to walk
# the AST and extract command references.  Classifies each command
# as a bash builtin, busyq applet, script-defined function, or
# external command.  Supports multiple output modes (report, json,
# applets list, cmake flag, etc.).
#
# Links: scan_main.o + libbusyq_scan.a + bash libs + ncurses
# Uses -Wl,--wrap=reader_loop to interpose our AST walker.
# Uses -Wl,--wrap=exit to support multi-file processing.
# =====================================================================
find_library(LIB_BUSYQ_SCAN busyq_scan PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)

if(LIB_BUSYQ_SCAN)
    add_executable(busyq-scan src/busyq_scan_main.c)

    target_include_directories(busyq-scan PRIVATE
        src
        "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/include"
    )

    # Collect bash libraries for linking (same as the main binary)
    set(SCAN_BASH_LIBS "")
    foreach(_lib LIB_BASH LIB_BUILTINS LIB_READLINE LIB_HISTORY LIB_GLOB LIB_TILDE LIB_SH)
        if(${_lib})
            list(APPEND SCAN_BASH_LIBS ${${_lib}})
        endif()
    endforeach()
    if(LIB_NCURSES)
        list(APPEND SCAN_BASH_LIBS ${LIB_NCURSES})
    endif()

    target_link_libraries(busyq-scan PRIVATE
        "${LIB_BUSYQ_SCAN}"
        ${SCAN_BASH_LIBS}
        m dl pthread
    )

    # Interpose reader_loop with our AST walker, exit for multi-file
    target_link_options(busyq-scan PRIVATE
        -static
        -Wl,--gc-sections
        -Wl,--wrap=reader_loop
        -Wl,--wrap=exit
    )
endif()

# =====================================================================
# Install
# =====================================================================
install(TARGETS busyq RUNTIME DESTINATION bin)

if(TARGET busyq-scan)
    install(TARGETS busyq-scan RUNTIME DESTINATION bin)
endif()

# Install the library and headers for custom builds
install(FILES "${BUSYQ_LIB}" DESTINATION lib OPTIONAL)
install(FILES src/applet_table.h src/applets.h DESTINATION include/busyq)
install(FILES src/applets.c DESTINATION share/busyq)
