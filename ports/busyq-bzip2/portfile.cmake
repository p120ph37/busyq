vcpkg_download_distfile(ARCHIVE
    URLS "https://sourceware.org/pub/bzip2/bzip2-1.0.8.tar.gz"
    FILENAME "bzip2-1.0.8.tar.gz"
    SHA512 0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
)

vcpkg_extract_source_archive(SOURCE_PATH ARCHIVE "${ARCHIVE}")

# Detect toolchain flags (CC, CFLAGS with LTO/optimization)
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

set(BZ_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(BZ_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

# bzip2 uses a plain Makefile — compile manually for full control.
# bzip2 dispatches on argv[0] for bunzip2/bzcat behavior.
set(BZ_BUILD_DIR "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")
file(MAKE_DIRECTORY "${BZ_BUILD_DIR}")
file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# Build all bzip2 source files
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e
        CC='${BZ_CC}'
        CFLAGS='${BZ_CFLAGS} -D_FILE_OFFSET_BITS=64'
        for f in blocksort.c huffman.c crctable.c randtable.c compress.c decompress.c bzlib.c bzip2.c; do
            \$CC \$CFLAGS -I'${SOURCE_PATH}' -c '${SOURCE_PATH}/'\$f -o \${f%.c}.o
        done
    "
    WORKING_DIRECTORY "${BZ_BUILD_DIR}"
    LOGNAME "compile-${TARGET_TRIPLET}"
)

# --- Symbol isolation ---
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e

        # Pack all objects into temporary archive
        ar rcs libbzip2_raw.a *.o

        # Combine into one relocatable .o
        ld -r --whole-archive libbzip2_raw.a -o bzip2_combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive libbzip2_raw.a -o bzip2_combined.o

        # Record undefined symbols (external deps: libc, etc.)
        nm -u bzip2_combined.o | sed 's/.* //' | sort -u > undef_syms.txt

        # Prefix all symbols with bz_
        objcopy --prefix-symbols=bz_ bzip2_combined.o

        # Generate redefine map to unprefix external deps
        sed 's/.*/bz_& &/' undef_syms.txt > redefine.map

        # Rename bz_main -> bzip2_main (entry point)
        echo 'bz_main bzip2_main' >> redefine.map

        objcopy --redefine-syms=redefine.map bzip2_combined.o

        # Package into final archive
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libbzip2.a' bzip2_combined.o
    "
    WORKING_DIRECTORY "${BZ_BUILD_DIR}"
    LOGNAME "symbol-isolate-${TARGET_TRIPLET}"
)

# Suppress vcpkg post-build warnings
set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

# Install copyright
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
