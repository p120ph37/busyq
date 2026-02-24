vcpkg_download_distfile(ARCHIVE
    URLS "https://ftpmirror.gnu.org/gnu/coreutils/coreutils-9.5.tar.xz"
         "https://mirrors.kernel.org/gnu/coreutils/coreutils-9.5.tar.xz"
         "https://ftp.gnu.org/gnu/coreutils/coreutils-9.5.tar.xz"
    FILENAME "coreutils-9.5.tar.xz"
    SHA512 2ca0deac4dc10a80fd0c6fd131252e99d457fd03b7bd626a6bc74fe5a0529c0a3d48ce1f5da1d3b3a7a150a1ce44f0fbb6b68a6ac543dfd5baa3e71f5d65401c
)

vcpkg_extract_source_archive(SOURCE_PATH ARCHIVE "${ARCHIVE}")

# Detect toolchain flags (CC, CFLAGS with LTO/optimization) before autotools
# claims the build directory.
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

set(CU_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(CU_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

# Build coreutils in single-binary mode.
# --enable-single-binary=symlinks: builds one 'coreutils' binary that
#   dispatches based on argv[0]. Each tool's main() is renamed to
#   single_binary_main_TOOLNAME() internally.
# --enable-no-install-program=stdbuf: stdbuf uses a shared library shim,
#   which is incompatible with our static-only approach.
# --without-libgmp: factor will use __int128 fallback (still handles large numbers)
# --without-openssl: no need for OpenSSL hash acceleration
# --without-selinux: not needed in distroless containers
# --disable-nls: no internationalization (smaller binary)
# FORCE_UNSAFE_CONFIGURE=1: allow running configure as root inside containers
set(ENV{FORCE_UNSAFE_CONFIGURE} "1")

vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --enable-single-binary=symlinks
        "--enable-no-install-program=stdbuf"
        --without-libgmp
        --without-openssl
        --without-selinux
        --disable-nls
        --disable-acl
        --disable-xattr
)

vcpkg_build_make()

set(CU_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# --- Symbol isolation ---
# Coreutils and bash both embed gnulib, causing massive symbol collisions
# (xmalloc, hash_insert, yyparse, etc.). Strategy:
#
# 1. Collect all .o files into a temporary archive
# 2. Use ld -r to combine into one relocatable object (resolves internal dupes)
# 3. Record all undefined symbols (= external deps: libc, pthreads, etc.)
# 4. Prefix ALL symbols with cu_ (namespaces everything)
# 5. Unprefix the external deps so they link against libc correctly
# 6. Rename cu_main → coreutils_main (our dispatch entry point)
# 7. Package into libcoreutils.a

# Step 1: Collect all object files from the build
file(GLOB_RECURSE CU_OBJS
    "${CU_BUILD_REL}/src/*.o"
    "${CU_BUILD_REL}/lib/*.o"
)
list(FILTER CU_OBJS EXCLUDE REGEX "/(tests|gnulib-tests|bench)/")

if(NOT CU_OBJS)
    message(FATAL_ERROR "No coreutils object files found in ${CU_BUILD_REL}")
endif()

# Step 1a: Pack into temporary archive (needed for ld -r --whole-archive)
vcpkg_execute_required_process(
    COMMAND ar rcs "${CU_BUILD_REL}/libcoreutils_raw.a" ${CU_OBJS}
    WORKING_DIRECTORY "${CU_BUILD_REL}"
    LOGNAME "ar-raw-${TARGET_TRIPLET}"
)

# Steps 2-6: Combine, prefix, unprefix, rename — all in one script
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e

        # Step 2: Combine all objects into one relocatable .o
        # --allow-multiple-definition resolves internal dupes (e.g. xalloc_die
        # defined in both gnulib and inlined into csplit.o)
        ld -r --whole-archive libcoreutils_raw.a -o coreutils_combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive libcoreutils_raw.a -o coreutils_combined.o

        # Step 3: Record undefined symbols (external deps: libc, pthreads, etc.)
        nm -u coreutils_combined.o | sed 's/.* //' | sort -u > undef_syms.txt

        # Step 4: Prefix all symbols with cu_
        objcopy --prefix-symbols=cu_ coreutils_combined.o

        # Step 5: Generate redefine map to unprefix external deps
        # After prefixing, 'malloc' became 'cu_malloc' (undefined).
        # Map it back: cu_malloc → malloc
        sed 's/.*/cu_& &/' undef_syms.txt > redefine.map

        # Step 6: Also rename cu_main → coreutils_main (dispatch entry point)
        echo 'cu_main coreutils_main' >> redefine.map

        objcopy --redefine-syms=redefine.map coreutils_combined.o

        # Step 7: Package into final archive
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libcoreutils.a' coreutils_combined.o
    "
    WORKING_DIRECTORY "${CU_BUILD_REL}"
    LOGNAME "symbol-isolate-${TARGET_TRIPLET}"
)

# Install copyright
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
