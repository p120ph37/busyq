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

# Rename main() at source level (LTO-safe — do NOT use -Dmain in CPPFLAGS,
# it breaks autotools helper programs)
busyq_rename_main(lzop "${SOURCE_PATH}/src/lzop.c")

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

set(LZOP_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# --- Symbol isolation ---
# Collect all .o files from lzop build
file(GLOB_RECURSE LZOP_OBJS
    "${LZOP_BUILD_REL}/src/*.o"
)
list(FILTER LZOP_OBJS EXCLUDE REGEX "/(tests)/")

if(NOT LZOP_OBJS)
    message(FATAL_ERROR "No lzop object files found in ${LZOP_BUILD_REL}")
endif()

# Pack into temporary archive
vcpkg_execute_required_process(
    COMMAND ar rcs "${LZOP_BUILD_REL}/lib_raw.a" ${LZOP_OBJS}
    WORKING_DIRECTORY "${LZOP_BUILD_REL}"
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
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/liblzop.a' combined.o
    "
    WORKING_DIRECTORY "${LZOP_BUILD_REL}"
    LOGNAME "combine-${TARGET_TRIPLET}"
)

# Suppress vcpkg post-build warnings
set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

# Install copyright
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
