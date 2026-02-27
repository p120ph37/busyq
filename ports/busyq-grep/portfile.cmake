vcpkg_download_distfile(ARCHIVE
    URLS "https://ftpmirror.gnu.org/gnu/grep/grep-3.11.tar.xz"
         "https://mirrors.kernel.org/gnu/grep/grep-3.11.tar.xz"
         "https://ftp.gnu.org/gnu/grep/grep-3.11.tar.xz"
    FILENAME "grep-3.11.tar.xz"
    SHA512 f254a1905a08c8173e12fbdd4fd8baed9a200217fba9d7641f0d78e4e002c1f2a621152d67027d9b25f0bb2430898f5233dc70909d8464fd13d7dd9298e65c42
)

vcpkg_extract_source_archive(SOURCE_PATH ARCHIVE "${ARCHIVE}")

# Detect toolchain flags (CC, CFLAGS with LTO/optimization) before autotools
# claims the build directory.
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

# Allow running configure as root inside containers
set(ENV{FORCE_UNSAFE_CONFIGURE} "1")

# --disable-nls: no internationalization (smaller binary)
# Let grep use its own bundled regex implementation for static linking
# compatibility (don't pass --without-included-regex).
# egrep/fgrep are shell script wrappers in modern GNU grep — we only
# need the 'grep' binary; egrep/fgrep can be shell aliases.
vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --disable-nls
)

vcpkg_build_make()

set(GREP_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# --- Symbol isolation ---
# grep embeds gnulib, causing symbol collisions with bash and other GNU tools.
# Strategy: prefix all symbols with grep_, then unprefix external deps.
# After prefixing, main becomes grep_main which IS the desired entry point.

# Step 1: Collect all object files from the build
file(GLOB_RECURSE GREP_OBJS
    "${GREP_BUILD_REL}/src/*.o"
    "${GREP_BUILD_REL}/lib/*.o"
)
list(FILTER GREP_OBJS EXCLUDE REGEX "/(tests|gnulib-tests)/")

if(NOT GREP_OBJS)
    message(FATAL_ERROR "No grep object files found in ${GREP_BUILD_REL}")
endif()

# Step 1a: Pack into temporary archive (needed for ld -r --whole-archive)
vcpkg_execute_required_process(
    COMMAND ar rcs "${GREP_BUILD_REL}/libgrep_raw.a" ${GREP_OBJS}
    WORKING_DIRECTORY "${GREP_BUILD_REL}"
    LOGNAME "ar-raw-${TARGET_TRIPLET}"
)

# Steps 2-7: Combine, prefix, unprefix, rename — all in one script
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e

        # Step 2: Combine all objects into one relocatable .o
        ld -r --whole-archive libgrep_raw.a -o grep_combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive libgrep_raw.a -o grep_combined.o

        # Step 3: Record undefined symbols (external deps: libc, pthreads, etc.)
        nm -u grep_combined.o | sed 's/.* //' | sort -u > undef_syms.txt

        # Step 4: Prefix all symbols with grep_
        objcopy --prefix-symbols=grep_ grep_combined.o

        # Step 5: Generate redefine map to unprefix external deps
        # After prefixing, 'malloc' became 'grep_malloc' (undefined).
        # Map it back: grep_malloc → malloc
        sed 's/.*/grep_& &/' undef_syms.txt > redefine.map

        # Step 6: Entry point — after prefixing, main became grep_main
        # which is already the desired entry point name. Add explicit
        # mapping to be self-documenting (it's a no-op).
        echo 'grep_main grep_main' >> redefine.map

        objcopy --redefine-syms=redefine.map grep_combined.o

        # Step 7: Package into final archive
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libgrep.a' grep_combined.o
    "
    WORKING_DIRECTORY "${GREP_BUILD_REL}"
    LOGNAME "symbol-isolate-${TARGET_TRIPLET}"
)

# Suppress vcpkg post-build warnings — we only produce release libraries
# and grep has no public headers (it's a tool, not a library)
set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

# Install copyright
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
