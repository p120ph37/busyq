include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_alpine_helpers.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_symbol_helpers.cmake")

busyq_alpine_source(
    PORT_DIR "${CMAKE_CURRENT_LIST_DIR}"
    OUT_SOURCE_PATH SOURCE_PATH
    USE_PATCH_CMD
)

# Detect toolchain flags
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

# Only build release (debug artifacts are unused)
set(VCPKG_BUILD_TYPE release)

# --- Generate compile-time symbol prefix header (LTO-safe) ---
set(_prefix_h "${SOURCE_PATH}/which_prefix.h")
busyq_gen_prefix_header(which "${_prefix_h}")

# Remove `savestring` from the prefix header.  GNU which bundles its own
# tilde.c (from readline) which uses `#if !defined(savestring)` to guard a
# local macro definition.  The prefix header's object-like macro
# `#define savestring which_savestring` makes that guard pass, so the local
# function-like macro is never defined, causing "undeclared function" errors.
# savestring is only used as a macro in which (never as a function symbol),
# so removing it from the prefix causes no linker collisions.
vcpkg_execute_required_process(
    COMMAND sed -i "/^#define savestring /d" "${_prefix_h}"
    WORKING_DIRECTORY "${CURRENT_BUILDTREES_DIR}"
    LOGNAME "fix-prefix-${TARGET_TRIPLET}"
)

set(WHICH_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(WHICH_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

set(ENV{FORCE_UNSAFE_CONFIGURE} "1")

vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --disable-nls
)

vcpkg_build_make(OPTIONS "CPPFLAGS=-include ${_prefix_h}")

# Rename main() after the build — doing it before would break the link step
busyq_post_build_rename_main(which "${_prefix_h}" "${SOURCE_PATH}/which.c")

set(WHICH_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# --- Symbol isolation ---
# GNU which is simple but may embed gnulib, so apply full isolation.


# Collect all object files from the build
file(GLOB WHICH_OBJS
    "${WHICH_BUILD_REL}/*.o"
)
file(GLOB WHICH_LIB_OBJS "${WHICH_BUILD_REL}/lib/*.o")
list(APPEND WHICH_OBJS ${WHICH_LIB_OBJS})

if(NOT WHICH_OBJS)
    message(FATAL_ERROR "No object files found in ${WHICH_BUILD_REL}")
endif()

# Pack into temporary archive (needed for ld -r --whole-archive)
vcpkg_execute_required_process(
    COMMAND ar rcs "${WHICH_BUILD_REL}/libwhich_raw.a" ${WHICH_OBJS}
    WORKING_DIRECTORY "${WHICH_BUILD_REL}"
    LOGNAME "ar-raw-${TARGET_TRIPLET}"
)
# Combine objects and package (no objcopy — compile-time prefix preserves bitcode)
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e
        ld -r --whole-archive libwhich_raw.a -o combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive libwhich_raw.a -o combined.o
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libwhich.a' combined.o
    "
    WORKING_DIRECTORY "${WHICH_BUILD_REL}"
    LOGNAME "combine-${TARGET_TRIPLET}"
)

set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
