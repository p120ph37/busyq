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

# Step 1a: Rename main in each tool's object file to avoid collisions
# when combining them with ld -r.
# find's main may be in find/ftsfind.o or find/find.o depending on version.
# xargs's main is in xargs/xargs.o.
# Note: shell variables ($obj) must use \$ to avoid cmake expansion.
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e
        # find's main is in find/ftsfind.o or find/find.o
        for obj in '${FU_BUILD_REL}/find/ftsfind.o' '${FU_BUILD_REL}/find/find.o'
do
            if [ -f \"\$obj\" ] && nm \"\$obj\" 2>/dev/null | grep -q ' T main\$'
then
                objcopy --redefine-sym main=find_main_orig \"\$obj\"
                break
            fi
        done
        # xargs's main is in xargs/xargs.o
        obj='${FU_BUILD_REL}/xargs/xargs.o'
        if [ -f \"\$obj\" ]
then
            objcopy --redefine-sym main=xargs_main_orig \"\$obj\"
        fi
    "
    WORKING_DIRECTORY "${FU_BUILD_REL}"
    LOGNAME "rename-mains-${TARGET_TRIPLET}"
)

# Step 1b: Pack into temporary archive (needed for ld -r --whole-archive)
vcpkg_execute_required_process(
    COMMAND ar rcs "${FU_BUILD_REL}/libfindutils_raw.a" ${FU_OBJS}
    WORKING_DIRECTORY "${FU_BUILD_REL}"
    LOGNAME "ar-raw-${TARGET_TRIPLET}"
)

# Steps 2-7: Combine, prefix, unprefix, rename — all in one script
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e

        # Step 2: Combine all objects into one relocatable .o
        ld -r --whole-archive libfindutils_raw.a -o findutils_combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive libfindutils_raw.a -o findutils_combined.o

        # Step 3: Record undefined symbols (external deps: libc, pthreads, etc.)
        nm -u findutils_combined.o | sed 's/.* //' | sort -u > undef_syms.txt

        # Step 4: Prefix all symbols with fu_
        objcopy --prefix-symbols=fu_ findutils_combined.o

        # Step 5: Generate redefine map to unprefix external deps
        # After prefixing, 'malloc' became 'fu_malloc' (undefined).
        # Map it back: fu_malloc → malloc
        sed 's/.*/fu_& &/' undef_syms.txt > redefine.map

        # Step 6: Rename prefixed tool mains to final entry points
        # Before prefix: find_main_orig, xargs_main_orig
        # After prefix:  fu_find_main_orig, fu_xargs_main_orig
        # Final rename:  find_main, xargs_main
        echo 'fu_find_main_orig find_main' >> redefine.map
        echo 'fu_xargs_main_orig xargs_main' >> redefine.map

        objcopy --redefine-syms=redefine.map findutils_combined.o

        # Step 7: Package into final archive
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libfindutils.a' findutils_combined.o
    "
    WORKING_DIRECTORY "${FU_BUILD_REL}"
    LOGNAME "symbol-isolate-${TARGET_TRIPLET}"
)

# Suppress vcpkg post-build warnings — we only produce release libraries
# and findutils has no public headers (it's a tool, not a library)
set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

# Install copyright
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
