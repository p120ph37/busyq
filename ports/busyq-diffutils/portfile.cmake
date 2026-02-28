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

# Only build release (debug artifacts are unused)
set(VCPKG_BUILD_TYPE release)

# --- Generate compile-time symbol prefix header (LTO-safe) ---
set(_prefix_h "${SOURCE_PATH}/diff_prefix.h")
busyq_gen_prefix_header(diff "${_prefix_h}")

# Allow running configure as root inside containers
set(ENV{FORCE_UNSAFE_CONFIGURE} "1")

vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --disable-nls
)

vcpkg_build_make(OPTIONS "CPPFLAGS=-include ${_prefix_h}")

# Rename main() after the build — doing it before would break the link step
foreach(_tool diff cmp diff3 sdiff)
    busyq_post_build_rename_main(${_tool} "${_prefix_h}" "${SOURCE_PATH}/src/${_tool}.c")
endforeach()

set(DU_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# --- Symbol isolation ---
# diffutils has four separate commands (diff, cmp, diff3, sdiff), each with
# its own main(). Compile-time prefix header handles gnulib collisions.
# Individual main renames use objcopy --redefine-sym (safe for single symbols).

# Collect all object files from the build
file(GLOB_RECURSE DU_OBJS
    "${DU_BUILD_REL}/src/*.o"
    "${DU_BUILD_REL}/lib/*.o"
)
list(FILTER DU_OBJS EXCLUDE REGEX "/(tests|gnulib-tests)/")

if(NOT DU_OBJS)
    message(FATAL_ERROR "No diffutils object files found in ${DU_BUILD_REL}")
endif()

# Pack into temporary archive (mains already renamed at source level)
vcpkg_execute_required_process(
    COMMAND ar rcs "${DU_BUILD_REL}/libdiffutils_raw.a" ${DU_OBJS}
    WORKING_DIRECTORY "${DU_BUILD_REL}"
    LOGNAME "ar-raw-${TARGET_TRIPLET}"
)

# Combine objects and package (no --prefix-symbols — compile-time prefix preserves bitcode)
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e
        ld -r --whole-archive libdiffutils_raw.a -o combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive libdiffutils_raw.a -o combined.o
        llvm-objcopy --wildcard --keep-global-symbol='*_main' combined.o
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libdiffutils.a' combined.o
    "
    WORKING_DIRECTORY "${DU_BUILD_REL}"
    LOGNAME "combine-${TARGET_TRIPLET}"
)

# Suppress vcpkg post-build warnings — we only produce release libraries
# and diffutils has no public headers (it's a tool, not a library)
set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

# Install copyright
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
