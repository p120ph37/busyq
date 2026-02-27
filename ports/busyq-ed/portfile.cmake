vcpkg_download_distfile(ARCHIVE
    URLS "https://ftpmirror.gnu.org/gnu/ed/ed-1.20.2.tar.lz"
         "https://mirrors.kernel.org/gnu/ed/ed-1.20.2.tar.lz"
         "https://ftp.gnu.org/gnu/ed/ed-1.20.2.tar.lz"
    FILENAME "ed-1.20.2.tar.lz"
    SHA512 5efad386399035329892d8349500544f76e1b18406e164aae35af872c15a0935d412dd4a6996bd15b960d0e899857cc7d8657805f441b1b9f2ae3d73c73dcf4f
)

vcpkg_extract_source_archive(SOURCE_PATH ARCHIVE "${ARCHIVE}")

# Detect toolchain flags (CC, CFLAGS with LTO/optimization) before autotools
# claims the build directory.
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

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

vcpkg_execute_required_process(
    COMMAND make -j${VCPKG_CONCURRENCY}
    WORKING_DIRECTORY "${ED_BUILD_REL}"
    LOGNAME "build-${TARGET_TRIPLET}"
)

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# --- Symbol isolation ---
# ed is a standalone tool but may have symbol collisions with other packages.
# Strategy: prefix all symbols with ed_, then unprefix external deps.
# After prefixing, main becomes ed_main which IS the desired entry point.

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

# Steps 2-7: Combine, prefix, unprefix, rename — all in one script
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e

        # Step 2: Combine all objects into one relocatable .o
        ld -r --whole-archive libed_raw.a -o ed_combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive libed_raw.a -o ed_combined.o

        # Step 3: Record undefined symbols (external deps: libc, etc.)
        nm -u ed_combined.o | sed 's/.* //' | sort -u > undef_syms.txt

        # Step 4: Prefix all symbols with ed_
        objcopy --prefix-symbols=ed_ ed_combined.o

        # Step 5: Generate redefine map to unprefix external deps
        # After prefixing, 'malloc' became 'ed_malloc' (undefined).
        # Map it back: ed_malloc → malloc
        sed 's/.*/ed_& &/' undef_syms.txt > redefine.map

        # Step 6: Entry point — after prefixing, main became ed_main
        # which is already the desired entry point name. Add explicit
        # mapping to be self-documenting (it's a no-op).
        echo 'ed_main ed_main' >> redefine.map

        objcopy --redefine-syms=redefine.map ed_combined.o

        # Step 7: Package into final archive
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libed.a' ed_combined.o
    "
    WORKING_DIRECTORY "${ED_BUILD_REL}"
    LOGNAME "symbol-isolate-${TARGET_TRIPLET}"
)

# Suppress vcpkg post-build warnings — we only produce release libraries
# and ed has no public headers (it's a tool, not a library)
set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

# Install copyright
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
