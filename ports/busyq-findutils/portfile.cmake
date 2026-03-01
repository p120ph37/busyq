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
set(_prefix_h "${SOURCE_PATH}/fu_prefix.h")
busyq_gen_prefix_header(fu "${_prefix_h}")

# Allow running configure as root inside containers
set(ENV{FORCE_UNSAFE_CONFIGURE} "1")

vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --disable-nls
)

vcpkg_build_make(OPTIONS "CPPFLAGS=-include ${_prefix_h}")

# Rename main() after the build — doing it before would break the link step
busyq_post_build_rename_main(find "${_prefix_h}"
    "${SOURCE_PATH}/find/ftsfind.c"
    "${SOURCE_PATH}/find/find.c"
)
busyq_post_build_rename_main(xargs "${_prefix_h}"
    "${SOURCE_PATH}/xargs/xargs.c"
)

set(FU_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

# Collect all object files from the build
file(GLOB_RECURSE FU_OBJS
    "${FU_BUILD_REL}/find/*.o"
    "${FU_BUILD_REL}/xargs/*.o"
    "${FU_BUILD_REL}/lib/*.o"
    "${FU_BUILD_REL}/gl/*.o"
)
list(FILTER FU_OBJS EXCLUDE REGEX "/(tests|gnulib-tests)/")

if(NOT FU_OBJS)
    message(FATAL_ERROR "No findutils object files found in ${FU_BUILD_REL}")
endif()

busyq_package_objects(libfindutils.a "${FU_BUILD_REL}" OBJECTS ${FU_OBJS})

busyq_finalize_port()
