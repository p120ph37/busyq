include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_alpine_helpers.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_symbol_helpers.cmake")

busyq_alpine_source(
    PORT_DIR "${CMAKE_CURRENT_LIST_DIR}"
    OUT_SOURCE_PATH SOURCE_PATH
)

# Detect toolchain flags
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

# Only build release (debug artifacts are unused)
set(VCPKG_BUILD_TYPE release)

# --- Generate compile-time symbol prefix header (LTO-safe) ---
set(_prefix_h "${SOURCE_PATH}/less_prefix.h")
busyq_gen_prefix_header(less "${_prefix_h}")

set(LESS_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(LESS_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
)

vcpkg_build_make(OPTIONS "CPPFLAGS=-include ${_prefix_h}")

# Rename main() after the build — doing it before would break the link step
busyq_post_build_rename_main(less "${_prefix_h}" "${SOURCE_PATH}/main.c")

set(LESS_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

# --- Symbol isolation ---
# less embeds its own utility functions that may collide with other packages.

# Collect all object files from the build
file(GLOB LESS_OBJS
    "${LESS_BUILD_REL}/*.o"
)

if(NOT LESS_OBJS)
    message(FATAL_ERROR "No object files found in ${LESS_BUILD_REL}")
endif()

busyq_package_objects(libless.a "${LESS_BUILD_REL}" OBJECTS ${LESS_OBJS})

busyq_finalize_port(COPYRIGHT "${SOURCE_PATH}/COPYING" "${SOURCE_PATH}/LICENSE")
