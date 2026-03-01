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
set(_prefix_h "${SOURCE_PATH}/diff_prefix.h")
busyq_gen_prefix_header(diff "${_prefix_h}")

# Allow running configure as root inside containers
set(ENV{FORCE_UNSAFE_CONFIGURE} "1")

vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --disable-nls
)

vcpkg_build_make(OPTIONS "CPPFLAGS=-include ${_prefix_h}")

# Rename main() after the build — doing it before would break the link step
foreach(_tool diff cmp diff3 sdiff)
    busyq_post_build_rename_main(${_tool} "${_prefix_h}" "${SOURCE_PATH}/src/${_tool}.c")
endforeach()

set(DU_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

# Collect all object files from the build
file(GLOB_RECURSE DU_OBJS
    "${DU_BUILD_REL}/src/*.o"
    "${DU_BUILD_REL}/lib/*.o"
)
list(FILTER DU_OBJS EXCLUDE REGEX "/(tests|gnulib-tests)/")

if(NOT DU_OBJS)
    message(FATAL_ERROR "No diffutils object files found in ${DU_BUILD_REL}")
endif()

busyq_package_objects(libdiffutils.a "${DU_BUILD_REL}" OBJECTS ${DU_OBJS})

busyq_finalize_port()
