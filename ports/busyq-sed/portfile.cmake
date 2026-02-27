vcpkg_download_distfile(ARCHIVE
    URLS "https://ftpmirror.gnu.org/gnu/sed/sed-4.9.tar.xz"
         "https://mirrors.kernel.org/gnu/sed/sed-4.9.tar.xz"
         "https://ftp.gnu.org/gnu/sed/sed-4.9.tar.xz"
    FILENAME "sed-4.9.tar.xz"
    SHA512 0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
)

vcpkg_extract_source_archive(SOURCE_PATH ARCHIVE "${ARCHIVE}")

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
        --disable-acl
)

vcpkg_build_make()

set(SED_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# --- Symbol isolation ---
# sed embeds gnulib, causing symbol collisions with bash and other GNU tools.
# Strategy: prefix all symbols with sed_, then unprefix external deps.
# After prefixing, main becomes sed_main which IS the desired entry point.

# Step 1: Collect all object files from the build
file(GLOB_RECURSE SED_OBJS
    "${SED_BUILD_REL}/sed/*.o"
    "${SED_BUILD_REL}/lib/*.o"
)
list(FILTER SED_OBJS EXCLUDE REGEX "/(tests|gnulib-tests)/")

if(NOT SED_OBJS)
    message(FATAL_ERROR "No sed object files found in ${SED_BUILD_REL}")
endif()

# Step 1a: Pack into temporary archive (needed for ld -r --whole-archive)
vcpkg_execute_required_process(
    COMMAND ar rcs "${SED_BUILD_REL}/libsed_raw.a" ${SED_OBJS}
    WORKING_DIRECTORY "${SED_BUILD_REL}"
    LOGNAME "ar-raw-${TARGET_TRIPLET}"
)

# Steps 2-7: Combine, prefix, unprefix, rename — all in one script
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e

        # Step 2: Combine all objects into one relocatable .o
        ld -r --whole-archive libsed_raw.a -o sed_combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive libsed_raw.a -o sed_combined.o

        # Step 3: Record undefined symbols (external deps: libc, pthreads, etc.)
        nm -u sed_combined.o | sed 's/.* //' | sort -u > undef_syms.txt

        # Step 4: Prefix all symbols with sed_
        objcopy --prefix-symbols=sed_ sed_combined.o

        # Step 5: Generate redefine map to unprefix external deps
        # After prefixing, 'malloc' became 'sed_malloc' (undefined).
        # Map it back: sed_malloc → malloc
        sed 's/.*/sed_& &/' undef_syms.txt > redefine.map

        # Step 6: Entry point — after prefixing, main became sed_main
        # which is already the desired entry point name. Add explicit
        # mapping to be self-documenting (it's a no-op).
        echo 'sed_main sed_main' >> redefine.map

        objcopy --redefine-syms=redefine.map sed_combined.o

        # Step 7: Package into final archive
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libsed.a' sed_combined.o
    "
    WORKING_DIRECTORY "${SED_BUILD_REL}"
    LOGNAME "symbol-isolate-${TARGET_TRIPLET}"
)

# Suppress vcpkg post-build warnings — we only produce release libraries
# and sed has no public headers (it's a tool, not a library)
set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

# Install copyright
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
