vcpkg_download_distfile(ARCHIVE
    URLS "https://ftpmirror.gnu.org/gnu/gawk/gawk-5.3.1.tar.xz"
         "https://mirrors.kernel.org/gnu/gawk/gawk-5.3.1.tar.xz"
         "https://ftp.gnu.org/gnu/gawk/gawk-5.3.1.tar.xz"
    FILENAME "gawk-5.3.1.tar.xz"
    SHA512 c6b4c50ce565e6355ca162955072471e37541c51855c0011e834243a7390db8811344b0c974335844770e408e1f63d72d0d81459a081c392e0245c726019eaff
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
        --without-readline
        --without-mpfr
        --disable-extensions
        --disable-nls
)

vcpkg_build_make()

set(GAWK_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# --- Symbol isolation ---
# gawk embeds gnulib and has its own yacc/lex symbols that collide with bash.
# Strategy: prefix all symbols with gawk_, then unprefix external deps.
# After prefixing, main becomes gawk_main which IS the desired entry point.

# Step 1: Collect all object files from the build
file(GLOB_RECURSE GAWK_OBJS
    "${GAWK_BUILD_REL}/*.o"
)
list(FILTER GAWK_OBJS EXCLUDE REGEX "/(tests|test|extension|extras)/")

if(NOT GAWK_OBJS)
    message(FATAL_ERROR "No gawk object files found in ${GAWK_BUILD_REL}")
endif()

# Step 1a: Pack into temporary archive (needed for ld -r --whole-archive)
vcpkg_execute_required_process(
    COMMAND ar rcs "${GAWK_BUILD_REL}/libgawk_raw.a" ${GAWK_OBJS}
    WORKING_DIRECTORY "${GAWK_BUILD_REL}"
    LOGNAME "ar-raw-${TARGET_TRIPLET}"
)

# Steps 2-7: Combine, prefix, unprefix, rename — all in one script
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e

        # Step 2: Combine all objects into one relocatable .o
        ld -r --whole-archive libgawk_raw.a -o gawk_combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive libgawk_raw.a -o gawk_combined.o

        # Step 3: Record undefined symbols (external deps: libc, pthreads, etc.)
        nm -u gawk_combined.o | sed 's/.* //' | sort -u > undef_syms.txt

        # Step 4: Prefix all symbols with gawk_
        objcopy --prefix-symbols=gawk_ gawk_combined.o

        # Step 5: Generate redefine map to unprefix external deps
        # After prefixing, 'malloc' became 'gawk_malloc' (undefined).
        # Map it back: gawk_malloc → malloc
        sed 's/.*/gawk_& &/' undef_syms.txt > redefine.map

        # Step 6: Entry point — after prefixing, main became gawk_main
        # which is already the desired entry point name. Add explicit
        # mapping to be self-documenting (it's a no-op).
        echo 'gawk_main gawk_main' >> redefine.map

        objcopy --redefine-syms=redefine.map gawk_combined.o

        # Step 7: Package into final archive
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libgawk.a' gawk_combined.o
    "
    WORKING_DIRECTORY "${GAWK_BUILD_REL}"
    LOGNAME "symbol-isolate-${TARGET_TRIPLET}"
)

# Suppress vcpkg post-build warnings — we only produce release libraries
# and gawk has no public headers (it's a tool, not a library)
set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

# Install copyright
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
