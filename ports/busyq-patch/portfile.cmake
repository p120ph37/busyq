include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_alpine_helpers.cmake")

busyq_alpine_source(
    PORT_DIR "${CMAKE_CURRENT_LIST_DIR}"
    OUT_SOURCE_PATH SOURCE_PATH
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

set(PATCH_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# --- Symbol isolation ---
# patch embeds gnulib, causing symbol collisions with bash and other GNU tools.
# Strategy: prefix all symbols with patch_, then unprefix external deps.
# After prefixing, main becomes patch_main which IS the desired entry point.

# Step 1: Collect all object files from the build
file(GLOB_RECURSE PATCH_OBJS
    "${PATCH_BUILD_REL}/src/*.o"
    "${PATCH_BUILD_REL}/lib/*.o"
)
list(FILTER PATCH_OBJS EXCLUDE REGEX "/(tests|gnulib-tests)/")

if(NOT PATCH_OBJS)
    message(FATAL_ERROR "No patch object files found in ${PATCH_BUILD_REL}")
endif()

# Step 1a: Pack into temporary archive (needed for ld -r --whole-archive)
vcpkg_execute_required_process(
    COMMAND ar rcs "${PATCH_BUILD_REL}/libpatch_raw.a" ${PATCH_OBJS}
    WORKING_DIRECTORY "${PATCH_BUILD_REL}"
    LOGNAME "ar-raw-${TARGET_TRIPLET}"
)

# Steps 2-7: Combine, prefix, unprefix, rename — all in one script
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e

        # Step 2: Combine all objects into one relocatable .o
        ld -r --whole-archive libpatch_raw.a -o patch_combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive libpatch_raw.a -o patch_combined.o

        # Step 3: Record undefined symbols (external deps: libc, pthreads, etc.)
        nm -u patch_combined.o | sed 's/.* //' | sort -u > undef_syms.txt

        # Step 4: Prefix all symbols with patch_
        objcopy --prefix-symbols=patch_ patch_combined.o

        # Step 5: Generate redefine map to unprefix external deps
        # After prefixing, 'malloc' became 'patch_malloc' (undefined).
        # Map it back: patch_malloc → malloc
        sed 's/.*/patch_& &/' undef_syms.txt > redefine.map

        # Step 6: Entry point — after prefixing, main became patch_main
        # which is already the desired entry point name. Add explicit
        # mapping to be self-documenting (it's a no-op).
        echo 'patch_main patch_main' >> redefine.map

        objcopy --redefine-syms=redefine.map patch_combined.o

        # Step 7: Package into final archive
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libpatch.a' patch_combined.o
    "
    WORKING_DIRECTORY "${PATCH_BUILD_REL}"
    LOGNAME "symbol-isolate-${TARGET_TRIPLET}"
)

# Suppress vcpkg post-build warnings — we only produce release libraries
# and patch has no public headers (it's a tool, not a library)
set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

# Install copyright
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
