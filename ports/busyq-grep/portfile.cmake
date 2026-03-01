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
set(_prefix_h "${SOURCE_PATH}/grep_prefix.h")
busyq_gen_prefix_header(grep "${_prefix_h}")

# Allow running configure as root inside containers
set(ENV{FORCE_UNSAFE_CONFIGURE} "1")

# --disable-nls: no internationalization (smaller binary)
# Let grep use its own bundled regex implementation for static linking
# compatibility (don't pass --without-included-regex).
# egrep/fgrep are shell script wrappers in modern GNU grep — we only
# need the 'grep' binary; egrep/fgrep can be shell aliases.
vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --disable-nls
)

vcpkg_build_make(OPTIONS "CPPFLAGS=-include ${_prefix_h}")

# Rename main() after the build — doing it before would break the link step
busyq_post_build_rename_main(grep "${_prefix_h}" "${SOURCE_PATH}/src/grep.c")

set(GREP_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

# --- Symbol isolation ---
# grep embeds gnulib, causing symbol collisions with bash and other GNU tools.
# Strategy: prefix all symbols with grep_, then unprefix external deps.
# After prefixing, main becomes grep_main which IS the desired entry point.

# Collect all object files from the build
file(GLOB_RECURSE GREP_OBJS
    "${GREP_BUILD_REL}/src/*.o"
    "${GREP_BUILD_REL}/lib/*.o"
)
list(FILTER GREP_OBJS EXCLUDE REGEX "/(tests|gnulib-tests)/")

if(NOT GREP_OBJS)
    message(FATAL_ERROR "No object files found in ${GREP_BUILD_REL}")
endif()

busyq_package_objects(libgrep.a "${GREP_BUILD_REL}" OBJECTS ${GREP_OBJS})

busyq_finalize_port()
