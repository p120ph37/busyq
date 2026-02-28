include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_alpine_helpers.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_symbol_helpers.cmake")

busyq_alpine_source(
    PORT_DIR "${CMAKE_CURRENT_LIST_DIR}"
    OUT_SOURCE_PATH SOURCE_PATH
    USE_PATCH_CMD
)

# Detect toolchain flags (CC, CFLAGS with LTO/optimization) before autotools
# claims the build directory.
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

# --- Generate compile-time symbol prefix header (LTO-safe) ---
set(_prefix_h "${SOURCE_PATH}/lsof_prefix.h")
busyq_gen_prefix_header(lsof "${_prefix_h}")

set(LSOF_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(LSOF_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

# Build lsof with autotools (modern lsof >= 4.99.0 uses autotools).
# FORCE_UNSAFE_CONFIGURE=1: allow running configure as root inside containers
set(ENV{FORCE_UNSAFE_CONFIGURE} "1")

# Rename main() at source level (LTO-safe — do NOT use -Dmain in CPPFLAGS,
# it breaks autotools helper programs)
busyq_rename_main(lsof
    "${SOURCE_PATH}/src/lsof.c"
    "${SOURCE_PATH}/src/main.c"
    "${SOURCE_PATH}/lsof.c"
)

vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --disable-shared
        --enable-static
)

# lsof 4.99.5 builds man pages requiring soelim (groff). Build only the
# binary and library targets we need, skipping documentation.
vcpkg_build_make(BUILD_TARGET lsof OPTIONS "CPPFLAGS=-include ${_prefix_h}")

set(LSOF_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# --- Symbol isolation ---
# lsof is a single-binary tool with one main(). Strategy:
#
# 1. Collect all .o files from the build
# 2. Combine into one relocatable object with ld -r
# 3. Record undefined symbols (external deps: libc, etc.)
# 4. Prefix ALL symbols with lsof_
# 5. Unprefix external deps so libc calls work
# 6. Rename lsof_main → lsof_main (our entry point)
# 7. Package into liblsof.a


# Collect all object files from the build
file(GLOB_RECURSE LSOF_OBJS
    "${LSOF_BUILD_REL}/src/*.o"
    "${LSOF_BUILD_REL}/lib/*.o"
)
list(FILTER LSOF_OBJS EXCLUDE REGEX "/(tests|testsuite|man|doc)/")

if(NOT LSOF_OBJS)
    message(FATAL_ERROR "No object files found in ${LSOF_BUILD_REL}")
endif()

# Pack into temporary archive (needed for ld -r --whole-archive)
vcpkg_execute_required_process(
    COMMAND ar rcs "${LSOF_BUILD_REL}/liblsof_raw.a" ${LSOF_OBJS}
    WORKING_DIRECTORY "${LSOF_BUILD_REL}"
    LOGNAME "ar-raw-${TARGET_TRIPLET}"
)
# Combine objects and package (no objcopy — compile-time prefix preserves bitcode)
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e
        ld -r --whole-archive liblsof_raw.a -o combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive liblsof_raw.a -o combined.o
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/liblsof.a' combined.o
    "
    WORKING_DIRECTORY "${LSOF_BUILD_REL}"
    LOGNAME "combine-${TARGET_TRIPLET}"
)

# Suppress vcpkg post-build warnings — we only produce release libraries
# and lsof has no public headers needed by busyq (it's a tool, not a library API)
set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

# Install copyright
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
