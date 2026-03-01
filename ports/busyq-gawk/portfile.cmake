include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_alpine_helpers.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_symbol_helpers.cmake")

busyq_alpine_source(
    PORT_DIR "${CMAKE_CURRENT_LIST_DIR}"
    OUT_SOURCE_PATH SOURCE_PATH
    USE_PATCH_CMD
    EXTRA_PATCHES "${CMAKE_CURRENT_LIST_DIR}/patches/custom/fix-extension-makefile-sed.patch"
)

# Detect toolchain flags (CC, CFLAGS with LTO/optimization) before autotools
# claims the build directory.
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

# Only build release (debug artifacts are unused)
set(VCPKG_BUILD_TYPE release)

# --- Generate compile-time symbol prefix header (LTO-safe) ---
set(_prefix_h "${SOURCE_PATH}/gawk_prefix.h")
busyq_gen_prefix_header(gawk "${_prefix_h}")

# Allow running configure as root inside containers
set(ENV{FORCE_UNSAFE_CONFIGURE} "1")

vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --without-readline
        --without-mpfr
        --disable-extensions
        --disable-nls
)

vcpkg_build_make(OPTIONS "CPPFLAGS=-include ${_prefix_h}")

# Rename main() after the build — doing it before would break the link step
busyq_post_build_rename_main(gawk "${_prefix_h}" "${SOURCE_PATH}/main.c")

set(GAWK_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

# --- Symbol isolation ---
# gawk embeds gnulib and has its own yacc/lex symbols that collide with bash.
# Strategy: prefix all symbols with gawk_, then unprefix external deps.
# After prefixing, main becomes gawk_main which IS the desired entry point.

# Collect all object files from the build
file(GLOB_RECURSE GAWK_OBJS
    "${GAWK_BUILD_REL}/*.o"
)
list(FILTER GAWK_OBJS EXCLUDE REGEX "/(tests|test|extension|extras)/")

if(NOT GAWK_OBJS)
    message(FATAL_ERROR "No object files found in ${GAWK_BUILD_REL}")
endif()

busyq_package_objects(libgawk.a "${GAWK_BUILD_REL}" OBJECTS ${GAWK_OBJS})

busyq_finalize_port()
