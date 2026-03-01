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
set(_prefix_h "${SOURCE_PATH}/gz_prefix.h")
busyq_gen_prefix_header(gz "${_prefix_h}")

set(GZ_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(GZ_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

# gzip uses argv[0] to determine mode:
#   gzip    = compress
#   gunzip  = decompress
#   zcat    = decompress to stdout
set(ENV{FORCE_UNSAFE_CONFIGURE} "1")

vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --disable-nls
)

vcpkg_build_make(OPTIONS "CPPFLAGS=-include ${_prefix_h}")

# Rename main() after the build — doing it before would break the link step
busyq_post_build_rename_main(gzip "${_prefix_h}" "${SOURCE_PATH}/gzip.c")

set(GZ_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

# --- Symbol isolation ---
# Collect all .o files from gzip build
file(GLOB_RECURSE GZ_OBJS
    "${GZ_BUILD_REL}/*.o"
)
list(FILTER GZ_OBJS EXCLUDE REGEX "/(tests|gnulib-tests)/")

if(NOT GZ_OBJS)
    message(FATAL_ERROR "No gzip object files found in ${GZ_BUILD_REL}")
endif()

busyq_package_objects(libgzip.a "${GZ_BUILD_REL}" OBJECTS ${GZ_OBJS})

busyq_finalize_port()
