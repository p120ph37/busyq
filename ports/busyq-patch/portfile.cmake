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

# --- Generate compile-time symbol prefix header (LTO-safe) ---
set(_prefix_h "${SOURCE_PATH}/patch_prefix.h")
busyq_gen_prefix_header(patch "${_prefix_h}")

# Allow running configure as root inside containers
set(ENV{FORCE_UNSAFE_CONFIGURE} "1")

vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --disable-nls
)

vcpkg_build_make(OPTIONS "CPPFLAGS=-include ${_prefix_h} -Dmain=patch_main")

set(PATCH_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# --- Symbol isolation ---
# patch embeds gnulib, causing symbol collisions with bash and other GNU tools.
# Strategy: prefix all symbols with patch_, then unprefix external deps.
# After prefixing, main becomes patch_main which IS the desired entry point.


# Collect all object files from the build
file(GLOB_RECURSE PATCH_OBJS
    "${PATCH_BUILD_REL}/src/*.o"
    "${PATCH_BUILD_REL}/lib/*.o"
)
list(FILTER PATCH_OBJS EXCLUDE REGEX "/(tests|gnulib-tests)/")

if(NOT PATCH_OBJS)
    message(FATAL_ERROR "No object files found in ${PATCH_BUILD_REL}")
endif()

# Pack into temporary archive (needed for ld -r --whole-archive)
vcpkg_execute_required_process(
    COMMAND ar rcs "${PATCH_BUILD_REL}/libpatch_raw.a" ${PATCH_OBJS}
    WORKING_DIRECTORY "${PATCH_BUILD_REL}"
    LOGNAME "ar-raw-${TARGET_TRIPLET}"
)
# Combine objects and package (no objcopy — compile-time prefix preserves bitcode)
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e
        ld -r --whole-archive libpatch_raw.a -o combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive libpatch_raw.a -o combined.o
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libpatch.a' combined.o
    "
    WORKING_DIRECTORY "${PATCH_BUILD_REL}"
    LOGNAME "combine-${TARGET_TRIPLET}"
)

# Suppress vcpkg post-build warnings — we only produce release libraries
# and patch has no public headers (it's a tool, not a library)
set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

# Install copyright
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
