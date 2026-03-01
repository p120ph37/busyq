# busyq-bc portfile - GNU bc and dc, uses Alpine-synced source
#
# Version: 1.08.2 (synced from Alpine 3.23-stable, zero patches)

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
set(_prefix_h "${SOURCE_PATH}/bc_prefix.h")
busyq_gen_prefix_header(bc "${_prefix_h}")

set(BC_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(BC_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

set(ENV{FORCE_UNSAFE_CONFIGURE} "1")

vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --disable-nls
        --with-readline=no
)

vcpkg_build_make(OPTIONS "CPPFLAGS=-include ${_prefix_h}")

# Rename main() after the build — doing it before would break the link step
busyq_post_build_rename_main(bc "${_prefix_h}"
    "${SOURCE_PATH}/bc/main.c"
    "${SOURCE_PATH}/bc/bc.c"
)
busyq_post_build_rename_main(dc "${_prefix_h}"
    "${SOURCE_PATH}/dc/main.c"
    "${SOURCE_PATH}/dc/dc.c"
)

set(BC_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

file(GLOB BC_BC_OBJS "${BC_BUILD_REL}/bc/*.o")
file(GLOB BC_DC_OBJS "${BC_BUILD_REL}/dc/*.o")
file(GLOB BC_LIB_OBJS "${BC_BUILD_REL}/lib/*.o")

set(BC_ALL_OBJS ${BC_BC_OBJS} ${BC_DC_OBJS} ${BC_LIB_OBJS})

if(NOT BC_ALL_OBJS)
    message(FATAL_ERROR "No bc object files found in ${BC_BUILD_REL}")
endif()

busyq_package_objects(libbc.a "${BC_BUILD_REL}" OBJECTS ${BC_ALL_OBJS})

busyq_finalize_port()
