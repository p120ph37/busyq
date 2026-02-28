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

# --- Generate compile-time symbol prefix header (LTO-safe) ---
set(_prefix_h "${SOURCE_PATH}/tar_prefix.h")
busyq_gen_prefix_header(tar "${_prefix_h}")

set(TAR_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(TAR_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

set(ENV{FORCE_UNSAFE_CONFIGURE} "1")

# Rename main() at source level (LTO-safe — do NOT use -Dmain in CPPFLAGS,
# it breaks autotools helper programs)
busyq_rename_main(tar "${SOURCE_PATH}/src/tar.c")

vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --disable-nls
        --without-selinux
        --without-posix-acls
        --without-xattrs
)

vcpkg_build_make(OPTIONS "CPPFLAGS=-include ${_prefix_h}")

set(TAR_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

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

# Pack into temporary archive
vcpkg_execute_required_process(
    COMMAND ar rcs "${TAR_BUILD_REL}/lib_raw.a" ${TAR_OBJS}
    WORKING_DIRECTORY "${TAR_BUILD_REL}"
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
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libtar.a' combined.o
    "
    WORKING_DIRECTORY "${TAR_BUILD_REL}"
    LOGNAME "combine-${TARGET_TRIPLET}"
)

# Suppress vcpkg post-build warnings
set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

# Install copyright
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
