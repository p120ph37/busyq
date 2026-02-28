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
set(_prefix_h "${SOURCE_PATH}/fu_prefix.h")
busyq_gen_prefix_header(fu "${_prefix_h}")

# Allow running configure as root inside containers
set(ENV{FORCE_UNSAFE_CONFIGURE} "1")

# Rename main() at source level for each tool (LTO-safe — objcopy can't
# rename symbols in LLVM bitcode objects)
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e
        for f in find/ftsfind.c find/find.c; do
            if [ -f '${SOURCE_PATH}/'\"\$f\" ]; then
                sed -i '1i #define main find_main' '${SOURCE_PATH}/'\"\$f\"
                break
            fi
        done
        sed -i '1i #define main xargs_main' '${SOURCE_PATH}/xargs/xargs.c'
    "
    WORKING_DIRECTORY "${SOURCE_PATH}"
    LOGNAME "rename-mains-${TARGET_TRIPLET}"
)

vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --disable-nls
)

vcpkg_build_make(OPTIONS "CPPFLAGS=-include ${_prefix_h}")

set(FU_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# --- Symbol isolation ---
# findutils has two separate commands (find, xargs), each with its own main().
# Strategy:
# 1. Rename each tool's main to a unique name BEFORE combining with ld -r
# 2. Combine all objects + gnulib into one relocatable .o
# 3. Prefix all symbols with fu_
# 4. Unprefix external deps (libc, pthreads, etc.)
# 5. Rename fu_<tool>_main_orig → <tool>_main for each command

# Step 1: Collect all object files from the build
file(GLOB_RECURSE FU_OBJS
    "${FU_BUILD_REL}/find/*.o"
    "${FU_BUILD_REL}/xargs/*.o"
    "${FU_BUILD_REL}/lib/*.o"
    "${FU_BUILD_REL}/gl/*.o"
)
list(FILTER FU_OBJS EXCLUDE REGEX "/(tests|gnulib-tests)/")

if(NOT FU_OBJS)
    message(FATAL_ERROR "No findutils object files found in ${FU_BUILD_REL}")
endif()

# Step 1a: Pack objects into raw archive
vcpkg_execute_required_process(
    COMMAND ar rcs "${FU_BUILD_REL}/libfindutils_raw.a" ${FU_OBJS}
    WORKING_DIRECTORY "${FU_BUILD_REL}"
    LOGNAME "ar-raw-${TARGET_TRIPLET}"
)

# Combine objects and package (mains already renamed at source level)
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e

        # Combine all objects into one relocatable .o
        ld -r --whole-archive libfindutils_raw.a -o combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive libfindutils_raw.a -o combined.o

        # Package into final archive
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libfindutils.a' combined.o
    "
    WORKING_DIRECTORY "${FU_BUILD_REL}"
    LOGNAME "combine-${TARGET_TRIPLET}"
)

# Suppress vcpkg post-build warnings — we only produce release libraries
# and findutils has no public headers (it's a tool, not a library)
set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

# Install copyright
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
