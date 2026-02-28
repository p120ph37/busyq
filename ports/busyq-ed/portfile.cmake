include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_alpine_helpers.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_symbol_helpers.cmake")

busyq_alpine_source(
    PORT_DIR "${CMAKE_CURRENT_LIST_DIR}"
    OUT_SOURCE_PATH SOURCE_PATH
)

# Detect toolchain flags (CC, CFLAGS with LTO/optimization) before autotools
# claims the build directory.
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

# Only build release (debug artifacts are unused)
set(VCPKG_BUILD_TYPE release)

# --- Generate compile-time symbol prefix header (LTO-safe) ---
set(_prefix_h "${SOURCE_PATH}/ed_prefix.h")
busyq_gen_prefix_header(ed "${_prefix_h}")

set(ED_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(ED_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

# Allow running configure as root inside containers
set(ENV{FORCE_UNSAFE_CONFIGURE} "1")

set(ED_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

# Create build directory for out-of-tree build
file(MAKE_DIRECTORY "${ED_BUILD_REL}")

# GNU ed uses a custom configure script (not autoconf-generated), so we
# must configure and build manually. It does not support standard autotools
# options like --disable-shared or --host.
vcpkg_execute_required_process(
    COMMAND sh -c "
        CC='${ED_CC}' \
        CFLAGS='${ED_CFLAGS}' \
        '${SOURCE_PATH}/configure' \
            --prefix='${CURRENT_PACKAGES_DIR}'
    "
    WORKING_DIRECTORY "${ED_BUILD_REL}"
    LOGNAME "configure-${TARGET_TRIPLET}"
)

# Build with compile-time prefix header
vcpkg_execute_required_process(
    COMMAND make -j${VCPKG_CONCURRENCY} "CPPFLAGS=-include ${_prefix_h}"
    WORKING_DIRECTORY "${ED_BUILD_REL}"
    LOGNAME "build-${TARGET_TRIPLET}"
)

# Rename main() after the build — doing it before would break the link step
busyq_post_build_rename_main(ed "${_prefix_h}"
    "${SOURCE_PATH}/main.c"
    "${SOURCE_PATH}/ed.c"
    "${SOURCE_PATH}/main_loop.c"
)

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# --- Symbol isolation (no objcopy — compile-time prefix preserves bitcode) ---
# Step 1: Collect all object files from the build
file(GLOB ED_OBJS
    "${ED_BUILD_REL}/*.o"
)

if(NOT ED_OBJS)
    message(FATAL_ERROR "No ed object files found in ${ED_BUILD_REL}")
endif()

# Step 1a: Pack into temporary archive (needed for ld -r --whole-archive)
vcpkg_execute_required_process(
    COMMAND ar rcs "${ED_BUILD_REL}/libed_raw.a" ${ED_OBJS}
    WORKING_DIRECTORY "${ED_BUILD_REL}"
    LOGNAME "ar-raw-${TARGET_TRIPLET}"
)

# Combine into relocatable object and package
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e

        # Combine all objects into one relocatable .o
        ld -r --whole-archive libed_raw.a -o ed_combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive libed_raw.a -o ed_combined.o

        # Package into final archive
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libed.a' ed_combined.o
    "
    WORKING_DIRECTORY "${ED_BUILD_REL}"
    LOGNAME "combine-${TARGET_TRIPLET}"
)

# Suppress vcpkg post-build warnings — we only produce release libraries
# and ed has no public headers (it's a tool, not a library)
set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

# Install copyright
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
