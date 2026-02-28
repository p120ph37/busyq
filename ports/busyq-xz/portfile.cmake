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

# Rename main() at source level (LTO-safe — do NOT use -Dmain in CPPFLAGS,
# it breaks autotools helper programs)
busyq_rename_main(xz "${SOURCE_PATH}/src/xz/main.c")

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

set(XZ_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

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

# Pack into temporary archive
vcpkg_execute_required_process(
    COMMAND ar rcs "${XZ_BUILD_REL}/lib_raw.a" ${XZ_OBJS}
    WORKING_DIRECTORY "${XZ_BUILD_REL}"
    LOGNAME "ar-raw-${TARGET_TRIPLET}"
)

# Combine, prefix, unprefix, rename
# Combine objects and package (no objcopy — compile-time prefix preserves bitcode)
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e
        ld -r --whole-archive lib_raw.a -o combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive lib_raw.a -o combined.o
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libxz.a' combined.o
    "
    WORKING_DIRECTORY "${XZ_BUILD_REL}"
    LOGNAME "combine-${TARGET_TRIPLET}"
)

# Suppress vcpkg post-build warnings
set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

# Install copyright
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
