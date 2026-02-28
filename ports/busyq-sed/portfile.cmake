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
set(_prefix_h "${SOURCE_PATH}/sed_prefix.h")
busyq_gen_prefix_header(sed "${_prefix_h}")

# Allow running configure as root inside containers
set(ENV{FORCE_UNSAFE_CONFIGURE} "1")

# Rename main() at source level (LTO-safe — do NOT use -Dmain in CPPFLAGS,
# it breaks autotools helper programs)
busyq_rename_main(sed "${SOURCE_PATH}/sed/sed.c")

vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --disable-nls
        --disable-acl
)

vcpkg_build_make(OPTIONS "CPPFLAGS=-include ${_prefix_h}")

set(SED_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# --- Symbol isolation ---
# sed embeds gnulib, causing symbol collisions with bash and other GNU tools.
# Strategy: prefix all symbols with sed_, then unprefix external deps.
# After prefixing, main becomes sed_main which IS the desired entry point.


# Collect all object files from the build
file(GLOB_RECURSE SED_OBJS
    "${SED_BUILD_REL}/sed/*.o"
    "${SED_BUILD_REL}/lib/*.o"
)
list(FILTER SED_OBJS EXCLUDE REGEX "/(tests|gnulib-tests)/")

if(NOT SED_OBJS)
    message(FATAL_ERROR "No object files found in ${SED_BUILD_REL}")
endif()

# Pack into temporary archive (needed for ld -r --whole-archive)
vcpkg_execute_required_process(
    COMMAND ar rcs "${SED_BUILD_REL}/libsed_raw.a" ${SED_OBJS}
    WORKING_DIRECTORY "${SED_BUILD_REL}"
    LOGNAME "ar-raw-${TARGET_TRIPLET}"
)
# Combine objects and package (no objcopy — compile-time prefix preserves bitcode)
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e
        ld -r --whole-archive libsed_raw.a -o combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive libsed_raw.a -o combined.o
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libsed.a' combined.o
    "
    WORKING_DIRECTORY "${SED_BUILD_REL}"
    LOGNAME "combine-${TARGET_TRIPLET}"
)

# Suppress vcpkg post-build warnings — we only produce release libraries
# and sed has no public headers (it's a tool, not a library)
set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

# Install copyright
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
