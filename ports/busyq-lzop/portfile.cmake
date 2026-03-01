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
set(_prefix_h "${SOURCE_PATH}/lzop_prefix.h")
busyq_gen_prefix_header(lzop "${_prefix_h}")

set(LZOP_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(LZOP_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

set(ENV{FORCE_UNSAFE_CONFIGURE} "1")

# lzop depends on lzo2 library — find its headers and library from vcpkg
set(LZO_INCLUDE "${CURRENT_INSTALLED_DIR}/include")
set(LZO_LIB "${CURRENT_INSTALLED_DIR}/lib")

vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --disable-nls
        "CPPFLAGS=-I${LZO_INCLUDE}"
        "LDFLAGS=-L${LZO_LIB}"
)

vcpkg_build_make(OPTIONS "CPPFLAGS=-include ${_prefix_h}")

# Rename main() after the build — doing it before would break the link step
busyq_post_build_rename_main(lzop "${_prefix_h}" "${SOURCE_PATH}/src/lzop.c")

set(LZOP_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

# --- Symbol isolation ---
# Collect all .o files from lzop build
file(GLOB_RECURSE LZOP_OBJS
    "${LZOP_BUILD_REL}/src/*.o"
)
list(FILTER LZOP_OBJS EXCLUDE REGEX "/(tests)/")

if(NOT LZOP_OBJS)
    message(FATAL_ERROR "No lzop object files found in ${LZOP_BUILD_REL}")
endif()

busyq_package_objects(liblzop.a "${LZOP_BUILD_REL}" OBJECTS ${LZOP_OBJS})

busyq_finalize_port()
