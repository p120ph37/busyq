include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_alpine_helpers.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_symbol_helpers.cmake")

busyq_alpine_source(
    PORT_DIR "${CMAKE_CURRENT_LIST_DIR}"
    OUT_SOURCE_PATH SOURCE_PATH
)

# Detect toolchain flags (CC, CFLAGS with LTO/optimization) before autotools
# claims the build directory.
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

# Only build release (debug artifacts are unused)
set(VCPKG_BUILD_TYPE release)

# --- Generate compile-time symbol prefix header (LTO-safe) ---
set(_prefix_h "${SOURCE_PATH}/wget_prefix.h")
busyq_gen_prefix_header(wget "${_prefix_h}")

set(WGET_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(WGET_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

# Build wget without SSL (users have curl for HTTPS).
# wget embeds gnulib, so full symbol isolation is critical.
# --disable-nls: no internationalization (smaller binary)
# --without-ssl: no SSL support (curl handles HTTPS)
# --disable-ntlm: no NTLM authentication
# --disable-debug: no debug output
# --without-metalink: no metalink support
# --disable-pcre / --disable-pcre2: no regex matching
# --without-libuuid: no UUID support
# --without-libidn: no IDN support
# --without-zlib: no compression (curl already handles this)
# FORCE_UNSAFE_CONFIGURE=1: allow running configure as root inside containers
set(ENV{FORCE_UNSAFE_CONFIGURE} "1")

vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --disable-nls
        --without-ssl
        --disable-ntlm
        --disable-debug
        --without-metalink
        --disable-pcre
        --disable-pcre2
        --without-libuuid
        --without-libidn
        --without-zlib
)

vcpkg_build_make(OPTIONS "CPPFLAGS=-include ${_prefix_h}")

# Rename main() after the build — doing it before would break the link step
busyq_post_build_rename_main(wget "${_prefix_h}" "${SOURCE_PATH}/src/main.c")

set(WGET_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

# --- Symbol isolation ---
# wget embeds gnulib, causing symbol collisions with bash, coreutils, etc.

# Collect all object files from the build
file(GLOB_RECURSE WGET_OBJS
    "${WGET_BUILD_REL}/src/*.o"
    "${WGET_BUILD_REL}/lib/*.o"
)
list(FILTER WGET_OBJS EXCLUDE REGEX "/(tests|testenv|fuzz)/")

if(NOT WGET_OBJS)
    message(FATAL_ERROR "No object files found in ${WGET_BUILD_REL}")
endif()

busyq_package_objects(libwget.a "${WGET_BUILD_REL}" OBJECTS ${WGET_OBJS})

busyq_finalize_port()
