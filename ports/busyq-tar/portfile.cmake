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
set(_prefix_h "${SOURCE_PATH}/tar_prefix.h")
busyq_gen_prefix_header(tar "${_prefix_h}")

set(TAR_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(TAR_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

set(ENV{FORCE_UNSAFE_CONFIGURE} "1")

vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --disable-nls
        --without-selinux
        --without-posix-acls
        --without-xattrs
)

vcpkg_build_make(OPTIONS "CPPFLAGS=-include ${_prefix_h}")

# Rename main() after the build — doing it before would break the link step
busyq_post_build_rename_main(tar "${_prefix_h}" "${SOURCE_PATH}/src/tar.c")

set(TAR_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

# --- Symbol isolation ---
# Collect all .o files from tar build (src/ and lib/ directories)
file(GLOB_RECURSE TAR_OBJS
    "${TAR_BUILD_REL}/src/*.o"
    "${TAR_BUILD_REL}/lib/*.o"
    "${TAR_BUILD_REL}/gnu/*.o"
)
list(FILTER TAR_OBJS EXCLUDE REGEX "/(tests|gnulib-tests)/")

if(NOT TAR_OBJS)
    message(FATAL_ERROR "No tar object files found in ${TAR_BUILD_REL}")
endif()

busyq_package_objects(libtar.a "${TAR_BUILD_REL}" OBJECTS ${TAR_OBJS})

busyq_finalize_port()
