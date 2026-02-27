vcpkg_download_distfile(ARCHIVE
    URLS "https://ftpmirror.gnu.org/gnu/gzip/gzip-1.13.tar.xz"
         "https://mirrors.kernel.org/gnu/gzip/gzip-1.13.tar.xz"
         "https://ftp.gnu.org/gnu/gzip/gzip-1.13.tar.xz"
    FILENAME "gzip-1.13.tar.xz"
    SHA512 e3d4d4aa4b2e53fdad980620307257c91dfbbc40bcec9baa8d4e85e8327f55e2ece552c9baf209df7b66a07103ab92d4954ac53c86c57fbde5e1dd461143f94c
)

vcpkg_extract_source_archive(SOURCE_PATH ARCHIVE "${ARCHIVE}")

# Detect toolchain flags (CC, CFLAGS with LTO/optimization)
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

set(GZ_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(GZ_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

# gzip uses argv[0] to determine mode:
#   gzip    = compress
#   gunzip  = decompress
#   zcat    = decompress to stdout
set(ENV{FORCE_UNSAFE_CONFIGURE} "1")

vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --disable-nls
)

vcpkg_build_make()

set(GZ_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# --- Symbol isolation ---
# Collect all .o files from gzip build
file(GLOB_RECURSE GZ_OBJS
    "${GZ_BUILD_REL}/*.o"
)
list(FILTER GZ_OBJS EXCLUDE REGEX "/(tests|gnulib-tests)/")

if(NOT GZ_OBJS)
    message(FATAL_ERROR "No gzip object files found in ${GZ_BUILD_REL}")
endif()

# Pack into temporary archive
vcpkg_execute_required_process(
    COMMAND ar rcs "${GZ_BUILD_REL}/libgzip_raw.a" ${GZ_OBJS}
    WORKING_DIRECTORY "${GZ_BUILD_REL}"
    LOGNAME "ar-raw-${TARGET_TRIPLET}"
)

# Combine, prefix, unprefix, rename
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e

        # Combine all objects into one relocatable .o
        ld -r --whole-archive libgzip_raw.a -o gzip_combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive libgzip_raw.a -o gzip_combined.o

        # Record undefined symbols (external deps: libc, etc.)
        nm -u gzip_combined.o | sed 's/.* //' | sort -u > undef_syms.txt

        # Prefix all symbols with gz_
        objcopy --prefix-symbols=gz_ gzip_combined.o

        # Generate redefine map to unprefix external deps
        sed 's/.*/gz_& &/' undef_syms.txt > redefine.map

        # Rename gz_main -> gzip_main (entry point)
        echo 'gz_main gzip_main' >> redefine.map

        objcopy --redefine-syms=redefine.map gzip_combined.o

        # Package into final archive
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libgzip.a' gzip_combined.o
    "
    WORKING_DIRECTORY "${GZ_BUILD_REL}"
    LOGNAME "symbol-isolate-${TARGET_TRIPLET}"
)

# Suppress vcpkg post-build warnings
set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

# Install copyright
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
