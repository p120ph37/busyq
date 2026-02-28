include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_alpine_helpers.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_symbol_helpers.cmake")

busyq_alpine_source(
    PORT_DIR "${CMAKE_CURRENT_LIST_DIR}"
    OUT_SOURCE_PATH SOURCE_PATH
)

# Detect toolchain flags
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

# --- Generate compile-time symbol prefix header (LTO-safe) ---
set(_prefix_h "${SOURCE_PATH}/less_prefix.h")
busyq_gen_prefix_header(less "${_prefix_h}")

set(LESS_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(LESS_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
)

vcpkg_build_make(OPTIONS "CPPFLAGS=-include ${_prefix_h} -Dmain=less_main")

set(LESS_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# --- Symbol isolation ---
# less embeds its own utility functions that may collide with other packages.


# Collect all object files from the build
file(GLOB LESS_OBJS
    "${LESS_BUILD_REL}/*.o"
)

if(NOT LESS_OBJS)
    message(FATAL_ERROR "No object files found in ${LESS_BUILD_REL}")
endif()

# Pack into temporary archive (needed for ld -r --whole-archive)
vcpkg_execute_required_process(
    COMMAND ar rcs "${LESS_BUILD_REL}/libless_raw.a" ${LESS_OBJS}
    WORKING_DIRECTORY "${LESS_BUILD_REL}"
    LOGNAME "ar-raw-${TARGET_TRIPLET}"
)
# Combine objects and package (no objcopy — compile-time prefix preserves bitcode)
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e
        ld -r --whole-archive libless_raw.a -o combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive libless_raw.a -o combined.o
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libless.a' combined.o
    "
    WORKING_DIRECTORY "${LESS_BUILD_REL}"
    LOGNAME "combine-${TARGET_TRIPLET}"
)

set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING" "${SOURCE_PATH}/LICENSE")
