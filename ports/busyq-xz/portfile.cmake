include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_alpine_helpers.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_symbol_helpers.cmake")

busyq_alpine_source(
    PORT_DIR "${CMAKE_CURRENT_LIST_DIR}"
    OUT_SOURCE_PATH SOURCE_PATH
)

# Detect toolchain flags (CC, CFLAGS with LTO/optimization)
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

# Only build release (debug artifacts are unused)
set(VCPKG_BUILD_TYPE release)

# --- Generate compile-time symbol prefix header (LTO-safe) ---
set(_prefix_h "${SOURCE_PATH}/xz_prefix.h")
busyq_gen_prefix_header(xz "${_prefix_h}")

set(XZ_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(XZ_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

# xz dispatches on argv[0]: xz/unxz/xzcat/lzma/unlzma/lzcat
set(ENV{FORCE_UNSAFE_CONFIGURE} "1")

vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --disable-shared
        --enable-static
        --disable-nls
        --disable-doc
        --disable-lzmainfo
        --disable-lzma-links
        --disable-scripts
)

vcpkg_build_make(OPTIONS "CPPFLAGS=-include ${_prefix_h}")

# Rename main() after the build — doing it before would break the link step
busyq_post_build_rename_main(xz "${_prefix_h}" "${SOURCE_PATH}/src/xz/main.c")

set(XZ_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

# --- Symbol isolation ---
# Collect all .o files from xz build (src/xz/ for the tool, src/liblzma/ for the library,
# src/common/ for shared code, lib/ for gnulib)
file(GLOB_RECURSE XZ_OBJS
    "${XZ_BUILD_REL}/src/xz/*.o"
    "${XZ_BUILD_REL}/src/liblzma/*.o"
    "${XZ_BUILD_REL}/src/common/*.o"
    "${XZ_BUILD_REL}/lib/*.o"
)
list(FILTER XZ_OBJS EXCLUDE REGEX "/(tests|gnulib-tests)/")

if(NOT XZ_OBJS)
    message(FATAL_ERROR "No xz object files found in ${XZ_BUILD_REL}")
endif()

busyq_package_objects(libxz.a "${XZ_BUILD_REL}" OBJECTS ${XZ_OBJS})

busyq_finalize_port()
