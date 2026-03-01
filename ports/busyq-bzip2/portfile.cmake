include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_alpine_helpers.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_symbol_helpers.cmake")

busyq_alpine_source(
    PORT_DIR "${CMAKE_CURRENT_LIST_DIR}"
    OUT_SOURCE_PATH SOURCE_PATH
    USE_PATCH_CMD
)

# Detect toolchain flags (CC, CFLAGS with LTO/optimization)
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

# Only build release (debug artifacts are unused)
set(VCPKG_BUILD_TYPE release)

# --- Generate compile-time symbol prefix header (LTO-safe) ---
set(_prefix_h "${SOURCE_PATH}/bz_prefix.h")
busyq_gen_prefix_header(bz "${_prefix_h}")

set(BZ_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(BZ_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

# bzip2 uses a plain Makefile — compile manually for full control.
# bzip2 dispatches on argv[0] for bunzip2/bzcat behavior.
set(BZ_BUILD_DIR "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")
file(MAKE_DIRECTORY "${BZ_BUILD_DIR}")
file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# Build all bzip2 source files with compile-time prefix header
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e
        CC='${BZ_CC}'
        CFLAGS='${BZ_CFLAGS} -D_FILE_OFFSET_BITS=64 -include ${_prefix_h} -Dmain=bzip2_main'
        for f in blocksort.c huffman.c crctable.c randtable.c compress.c decompress.c bzlib.c bzip2.c
do
            \$CC \$CFLAGS -I'${SOURCE_PATH}' -c '${SOURCE_PATH}/'\$f -o \${f%.c}.o
        done
    "
    WORKING_DIRECTORY "${BZ_BUILD_DIR}"
    LOGNAME "compile-${TARGET_TRIPLET}"
)

# --- Symbol isolation (no objcopy — compile-time prefix preserves bitcode) ---
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e

        # Pack all objects into temporary archive
        ar rcs libbzip2_raw.a *.o

        # Combine into one relocatable .o
        ld -r --whole-archive libbzip2_raw.a -o bzip2_combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive libbzip2_raw.a -o bzip2_combined.o
        llvm-objcopy --wildcard --keep-global-symbol='*_main' bzip2_combined.o

        # Package into final archive
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libbzip2.a' bzip2_combined.o
    "
    WORKING_DIRECTORY "${BZ_BUILD_DIR}"
    LOGNAME "combine-${TARGET_TRIPLET}"
)

busyq_finalize_port(COPYRIGHT "${SOURCE_PATH}/LICENSE")
