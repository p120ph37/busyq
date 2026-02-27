include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_alpine_helpers.cmake")

busyq_alpine_source(
    PORT_DIR "${CMAKE_CURRENT_LIST_DIR}"
    OUT_SOURCE_PATH SOURCE_PATH
)

# Detect toolchain flags
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

set(LESS_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(LESS_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
)

vcpkg_build_make()

set(LESS_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# --- Symbol isolation ---
# less embeds its own utility functions that may collide with other packages.

# Step 1: Collect object files
file(GLOB LESS_OBJS "${LESS_BUILD_REL}/*.o")

if(NOT LESS_OBJS)
    message(FATAL_ERROR "No less object files found in ${LESS_BUILD_REL}")
endif()

# Step 1a: Pack into temporary archive
vcpkg_execute_required_process(
    COMMAND ar rcs "${LESS_BUILD_REL}/libless_raw.a" ${LESS_OBJS}
    WORKING_DIRECTORY "${LESS_BUILD_REL}"
    LOGNAME "ar-raw-${TARGET_TRIPLET}"
)

# Steps 2-7: Combine, prefix, unprefix, rename
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e

        # Combine into one relocatable object
        ld -r --whole-archive libless_raw.a -o less_combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive libless_raw.a -o less_combined.o

        # Record undefined symbols
        nm -u less_combined.o | sed 's/.* //' | sort -u > undef_syms.txt

        # Prefix all symbols with less_
        objcopy --prefix-symbols=less_ less_combined.o

        # Generate redefine map to unprefix external deps
        sed 's/.*/less_& &/' undef_syms.txt > redefine.map

        # Rename less_main -> less_main (entry point)
        echo 'less_main less_main' >> redefine.map

        objcopy --redefine-syms=redefine.map less_combined.o

        # Package into final archive
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libless.a' less_combined.o
    "
    WORKING_DIRECTORY "${LESS_BUILD_REL}"
    LOGNAME "symbol-isolate-${TARGET_TRIPLET}"
)

set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING" "${SOURCE_PATH}/LICENSE")
