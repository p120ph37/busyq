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

# --- Generate compile-time symbol prefix header (LTO-safe) ---
set(_prefix_h "${SOURCE_PATH}/which_prefix.h")
busyq_gen_prefix_header(which "${_prefix_h}")

set(WHICH_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(WHICH_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

set(ENV{FORCE_UNSAFE_CONFIGURE} "1")

# Rename main() at source level (LTO-safe — do NOT use -Dmain in CPPFLAGS,
# it breaks autotools helper programs)
busyq_rename_main(which "${SOURCE_PATH}/which.c")

vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --disable-nls
)

vcpkg_build_make(OPTIONS "CPPFLAGS=-include ${_prefix_h}")

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
