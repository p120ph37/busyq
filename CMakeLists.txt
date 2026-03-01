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
# Find libraries installed by our overlay ports
# These are found via CMAKE_PREFIX_PATH set by vcpkg toolchain
# =====================================================================

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

# SSL: mbedtls libraries (conditional)
if(BUSYQ_SSL)
    find_library(LIB_MBEDTLS mbedtls PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
    find_library(LIB_MBEDX509 mbedx509 PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
    find_library(LIB_MBEDCRYPTO mbedcrypto PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
endif()

# =====================================================================
# Assemble the ordered list of component libraries
# Link order matters for static libraries.
# =====================================================================
set(BUSYQ_COMPONENT_LIBS "")

# Bash
foreach(_lib LIB_BASH LIB_BUILTINS LIB_READLINE LIB_HISTORY LIB_GLOB LIB_TILDE LIB_SH)
    if(${_lib})
        list(APPEND BUSYQ_COMPONENT_LIBS ${${_lib}})
    endif()
endforeach()

# Coreutils
if(LIB_COREUTILS)
    list(APPEND BUSYQ_COMPONENT_LIBS ${LIB_COREUTILS})
endif()

# Phase 2: Text processing
foreach(_lib LIB_GAWK LIB_SED LIB_GREP LIB_DIFFUTILS LIB_FINDUTILS LIB_ED LIB_PATCH)
    if(${_lib})
        list(APPEND BUSYQ_COMPONENT_LIBS ${${_lib}})
    endif()
endforeach()

# Phase 3: Archival
foreach(_lib LIB_TAR LIB_GZIP LIB_BZIP2_TOOL LIB_XZ LIB_CPIO LIB_LZOP LIB_ZIP LIB_UNZIP)
    if(${_lib})
        list(APPEND BUSYQ_COMPONENT_LIBS ${${_lib}})
    endif()
endforeach()

# Phase 4: Small standalone tools
foreach(_lib LIB_BC LIB_LESS LIB_STRINGS LIB_TIME LIB_DOS2UNIX LIB_SHARUTILS LIB_TSET LIB_WHICH)
    if(${_lib})
        list(APPEND BUSYQ_COMPONENT_LIBS ${${_lib}})
    endif()
endforeach()

# Phase 5: Networking
foreach(_lib LIB_WGET LIB_NC LIB_PING LIB_HOSTNAME LIB_WHOIS)
    if(${_lib})
        list(APPEND BUSYQ_COMPONENT_LIBS ${${_lib}})
    endif()
endforeach()

# Phase 6: Process utilities
foreach(_lib LIB_PROCPS LIB_PSMISC LIB_LSOF)
    if(${_lib})
        list(APPEND BUSYQ_COMPONENT_LIBS ${${_lib}})
    endif()
endforeach()

# Curl
foreach(_lib LIB_CURLMAIN LIB_CURL LIB_NGHTTP2 LIB_Z LIB_BROTLIDEC LIB_BROTLICOMMON LIB_ZSTD)
    if(${_lib})
        list(APPEND BUSYQ_COMPONENT_LIBS ${${_lib}})
    endif()
endforeach()

# jq
foreach(_lib LIB_JQMAIN LIB_JQ LIB_ONIG)
    if(${_lib})
        list(APPEND BUSYQ_COMPONENT_LIBS ${${_lib}})
    endif()
endforeach()

# lzo (for lzop)
if(LIB_LZO)
    list(APPEND BUSYQ_COMPONENT_LIBS ${LIB_LZO})
endif()

# ncurses
if(LIB_NCURSES)
    list(APPEND BUSYQ_COMPONENT_LIBS ${LIB_NCURSES})
endif()

# SSL
if(BUSYQ_SSL)
    foreach(_lib LIB_MBEDTLS LIB_MBEDX509 LIB_MBEDCRYPTO)
        if(${_lib})
            list(APPEND BUSYQ_COMPONENT_LIBS ${${_lib}})
        endif()
    endforeach()
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
