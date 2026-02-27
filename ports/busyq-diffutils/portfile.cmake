include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_alpine_helpers.cmake")

busyq_alpine_source(
    PORT_DIR "${CMAKE_CURRENT_LIST_DIR}"
    OUT_SOURCE_PATH SOURCE_PATH
    USE_PATCH_CMD
)

# Detect toolchain flags (CC, CFLAGS with LTO/optimization) before autotools
# claims the build directory.
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

# Allow running configure as root inside containers
set(ENV{FORCE_UNSAFE_CONFIGURE} "1")

vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --disable-nls
)

vcpkg_build_make()

set(DU_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# --- Symbol isolation ---
# diffutils has four separate commands (diff, cmp, diff3, sdiff), each with
# its own main(). Strategy:
# 1. Rename each tool's main to a unique name BEFORE combining with ld -r
# 2. Combine all objects + gnulib into one relocatable .o
# 3. Prefix all symbols with diff_
# 4. Unprefix external deps (libc, pthreads, etc.)
# 5. Rename diff_<tool>_main_orig → <tool>_main for each command

# Step 1: Collect all object files from the build
file(GLOB_RECURSE DU_OBJS
    "${DU_BUILD_REL}/src/*.o"
    "${DU_BUILD_REL}/lib/*.o"
)
list(FILTER DU_OBJS EXCLUDE REGEX "/(tests|gnulib-tests)/")

if(NOT DU_OBJS)
    message(FATAL_ERROR "No diffutils object files found in ${DU_BUILD_REL}")
endif()

# Step 1a: Rename main in each tool's object file to avoid collisions
# when combining them with ld -r. Each tool gets main → <tool>_main_orig.
# Note: shell variables ($tool, $obj) must use \$ to avoid cmake expansion.
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e
        for tool in diff cmp diff3 sdiff
do
            obj='${DU_BUILD_REL}/src/'\"\$tool\".o
            if [ -f \"\$obj\" ]
then
                objcopy --redefine-sym main=\"\${tool}_main_orig\" \"\$obj\"
            fi
        done
    "
    WORKING_DIRECTORY "${DU_BUILD_REL}"
    LOGNAME "rename-mains-${TARGET_TRIPLET}"
)

# Step 1b: Pack into temporary archive (needed for ld -r --whole-archive)
vcpkg_execute_required_process(
    COMMAND ar rcs "${DU_BUILD_REL}/libdiffutils_raw.a" ${DU_OBJS}
    WORKING_DIRECTORY "${DU_BUILD_REL}"
    LOGNAME "ar-raw-${TARGET_TRIPLET}"
)

# Steps 2-7: Combine, prefix, unprefix, rename — all in one script
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e

        # Step 2: Combine all objects into one relocatable .o
        ld -r --whole-archive libdiffutils_raw.a -o diffutils_combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive libdiffutils_raw.a -o diffutils_combined.o

        # Step 3: Record undefined symbols (external deps: libc, pthreads, etc.)
        nm -u diffutils_combined.o | sed 's/.* //' | sort -u > undef_syms.txt

        # Step 4: Prefix all symbols with diff_
        objcopy --prefix-symbols=diff_ diffutils_combined.o

        # Step 5: Generate redefine map to unprefix external deps
        # After prefixing, 'malloc' became 'diff_malloc' (undefined).
        # Map it back: diff_malloc → malloc
        sed 's/.*/diff_& &/' undef_syms.txt > redefine.map

        # Step 6: Rename prefixed tool mains to final entry points
        # Before prefix: diff_main_orig, cmp_main_orig, etc.
        # After prefix:  diff_diff_main_orig, diff_cmp_main_orig, etc.
        # Final rename:  diff_main, cmp_main, diff3_main, sdiff_main
        echo 'diff_diff_main_orig diff_main' >> redefine.map
        echo 'diff_cmp_main_orig cmp_main' >> redefine.map
        echo 'diff_diff3_main_orig diff3_main' >> redefine.map
        echo 'diff_sdiff_main_orig sdiff_main' >> redefine.map

        objcopy --redefine-syms=redefine.map diffutils_combined.o

        # Step 7: Package into final archive
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libdiffutils.a' diffutils_combined.o
    "
    WORKING_DIRECTORY "${DU_BUILD_REL}"
    LOGNAME "symbol-isolate-${TARGET_TRIPLET}"
)

# Suppress vcpkg post-build warnings — we only produce release libraries
# and diffutils has no public headers (it's a tool, not a library)
set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

# Install copyright
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
