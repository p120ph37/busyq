include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_alpine_helpers.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_symbol_helpers.cmake")

busyq_alpine_source(
    PORT_DIR "${CMAKE_CURRENT_LIST_DIR}"
    OUT_SOURCE_PATH SOURCE_PATH
    USE_PATCH_CMD
)

# Detect toolchain flags (CC, CFLAGS with LTO/optimization)
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

# Only build release (debug artifacts are unused)
set(VCPKG_BUILD_TYPE release)

# --- Generate compile-time symbol prefix header (LTO-safe) ---
set(_prefix_h "${SOURCE_PATH}/cpio_prefix.h")
busyq_gen_prefix_header(cpio "${_prefix_h}")

set(CPIO_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(CPIO_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

set(ENV{FORCE_UNSAFE_CONFIGURE} "1")

vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --disable-nls
)

vcpkg_build_make(OPTIONS "CPPFLAGS=-include ${_prefix_h}")

# Rename main() after the build — doing it before would break the link step
busyq_post_build_rename_main(cpio "${_prefix_h}"
    "${SOURCE_PATH}/src/main.c"
    "${SOURCE_PATH}/src/cpio.c"
)

set(CPIO_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

# --- Symbol isolation ---
# Collect all .o files from cpio build
file(GLOB_RECURSE CPIO_OBJS
    "${CPIO_BUILD_REL}/src/*.o"
    "${CPIO_BUILD_REL}/lib/*.o"
    "${CPIO_BUILD_REL}/gnu/*.o"
)
list(FILTER CPIO_OBJS EXCLUDE REGEX "/(tests|gnulib-tests)/")

if(NOT CPIO_OBJS)
    message(FATAL_ERROR "No cpio object files found in ${CPIO_BUILD_REL}")
endif()

busyq_package_objects(libcpio.a "${CPIO_BUILD_REL}" OBJECTS ${CPIO_OBJS})

busyq_finalize_port()
