vcpkg_download_distfile(ARCHIVE
    URLS "https://ftpmirror.gnu.org/gnu/tar/tar-1.35.tar.xz"
         "https://mirrors.kernel.org/gnu/tar/tar-1.35.tar.xz"
         "https://ftp.gnu.org/gnu/tar/tar-1.35.tar.xz"
    FILENAME "tar-1.35.tar.xz"
    SHA512 8b84ed661e6c878fa33eb5c1808d20351e6f40551ac63f96014fb0d0b9c72d5d94d8865d39e36bcb184fd250f84778a3b271bbd8bd2ceb69eece0c3568577510
)

vcpkg_extract_source_archive(SOURCE_PATH ARCHIVE "${ARCHIVE}")

# Detect toolchain flags (CC, CFLAGS with LTO/optimization)
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

set(TAR_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(TAR_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

set(ENV{FORCE_UNSAFE_CONFIGURE} "1")

vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --disable-nls
        --without-selinux
        --without-posix-acls
        --without-xattrs
)

vcpkg_build_make()

set(TAR_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# --- Symbol isolation ---
# Collect all .o files from tar build (src/ and lib/ directories)
file(GLOB_RECURSE TAR_OBJS
    "${TAR_BUILD_REL}/src/*.o"
    "${TAR_BUILD_REL}/lib/*.o"
    "${TAR_BUILD_REL}/gnu/*.o"
)
list(FILTER TAR_OBJS EXCLUDE REGEX "/(tests|gnulib-tests)/")

if(NOT TAR_OBJS)
    message(FATAL_ERROR "No tar object files found in ${TAR_BUILD_REL}")
endif()

# Pack into temporary archive
vcpkg_execute_required_process(
    COMMAND ar rcs "${TAR_BUILD_REL}/libtar_raw.a" ${TAR_OBJS}
    WORKING_DIRECTORY "${TAR_BUILD_REL}"
    LOGNAME "ar-raw-${TARGET_TRIPLET}"
)

# Combine, prefix, unprefix, rename
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e

        # Combine all objects into one relocatable .o
        ld -r --whole-archive libtar_raw.a -o tar_combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive libtar_raw.a -o tar_combined.o

        # Record undefined symbols (external deps: libc, pthreads, etc.)
        nm -u tar_combined.o | sed 's/.* //' | sort -u > undef_syms.txt

        # Prefix all symbols with tar_
        objcopy --prefix-symbols=tar_ tar_combined.o

        # Generate redefine map to unprefix external deps
        sed 's/.*/tar_& &/' undef_syms.txt > redefine.map

        # Rename tar_main -> tar_main (entry point)
        echo 'tar_main tar_main' >> redefine.map

        objcopy --redefine-syms=redefine.map tar_combined.o

        # Package into final archive
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libtar.a' tar_combined.o
    "
    WORKING_DIRECTORY "${TAR_BUILD_REL}"
    LOGNAME "symbol-isolate-${TARGET_TRIPLET}"
)

# Suppress vcpkg post-build warnings
set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

# Install copyright
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
