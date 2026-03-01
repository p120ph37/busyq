include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_alpine_helpers.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_symbol_helpers.cmake")

busyq_alpine_source(
    PORT_DIR "${CMAKE_CURRENT_LIST_DIR}"
    OUT_SOURCE_PATH SOURCE_PATH
    USE_PATCH_CMD
)

# Detect toolchain flags (CC, CFLAGS with LTO/optimization) before autotools
# claims the build directory.
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

# Only build release (debug artifacts are unused)
set(VCPKG_BUILD_TYPE release)

# --- Generate compile-time symbol prefix header (LTO-safe) ---
set(_prefix_h "${SOURCE_PATH}/lsof_prefix.h")
busyq_gen_prefix_header(lsof "${_prefix_h}")

set(LSOF_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(LSOF_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

# Build lsof with autotools (modern lsof >= 4.99.0 uses autotools).
# FORCE_UNSAFE_CONFIGURE=1: allow running configure as root inside containers
set(ENV{FORCE_UNSAFE_CONFIGURE} "1")

vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --disable-shared
        --enable-static
)

# lsof 4.99.5 builds man pages requiring soelim (groff). Build only the
# binary and library targets we need, skipping documentation.
vcpkg_build_make(BUILD_TARGET lsof OPTIONS "CPPFLAGS=-include ${_prefix_h}")

# Rename main() after the build — doing it before would break the link step
busyq_post_build_rename_main(lsof "${_prefix_h}"
    "${SOURCE_PATH}/src/lsof.c"
    "${SOURCE_PATH}/src/main.c"
    "${SOURCE_PATH}/lsof.c"
)

set(LSOF_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

# --- Symbol isolation ---
# lsof is a single-binary tool with one main().

# Collect all object files from the build
file(GLOB_RECURSE LSOF_OBJS
    "${LSOF_BUILD_REL}/src/*.o"
    "${LSOF_BUILD_REL}/lib/*.o"
)
list(FILTER LSOF_OBJS EXCLUDE REGEX "/(tests|testsuite|man|doc)/")

if(NOT LSOF_OBJS)
    message(FATAL_ERROR "No object files found in ${LSOF_BUILD_REL}")
endif()

busyq_package_objects(liblsof.a "${LSOF_BUILD_REL}" OBJECTS ${LSOF_OBJS})

busyq_finalize_port()
