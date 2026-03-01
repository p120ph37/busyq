include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_alpine_helpers.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_symbol_helpers.cmake")

busyq_alpine_source(
    PORT_DIR "${CMAKE_CURRENT_LIST_DIR}"
    OUT_SOURCE_PATH SOURCE_PATH
)

# Detect toolchain flags
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

# Only build release (debug artifacts are unused)
set(VCPKG_BUILD_TYPE release)

# --- Generate compile-time symbol prefix header (LTO-safe) ---
set(_prefix_h "${SOURCE_PATH}/d2u_prefix.h")
busyq_gen_prefix_header(d2u "${_prefix_h}")

set(D2U_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(D2U_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

set(D2U_BUILD_DIR "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")
file(MAKE_DIRECTORY "${D2U_BUILD_DIR}")

# --- Compile and combine (compile-time prefix preserves bitcode) ---
# dos2unix and unix2dos are the same binary dispatching on argv[0].
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e

        PREFIX_FLAGS='-include ${_prefix_h} -Dmain=dos2unix_main'

        # Compile key source files with compile-time prefix
        ${D2U_CC} ${D2U_CFLAGS} \$PREFIX_FLAGS -I'${SOURCE_PATH}' -DVER_REVISION='\"7.5.2\"' -DVER_DATE='\"2024-01-22\"' \
            -DVER_AUTHOR='\"\"' -DDEBUG=0 -UD2U_UNIFILE \
            -c '${SOURCE_PATH}/dos2unix.c' -o dos2unix.o
        ${D2U_CC} ${D2U_CFLAGS} \$PREFIX_FLAGS -I'${SOURCE_PATH}' -DVER_REVISION='\"7.5.2\"' -DVER_DATE='\"2024-01-22\"' \
            -DDEBUG=0 -UD2U_UNIFILE \
            -c '${SOURCE_PATH}/querycp.c' -o querycp.o
        ${D2U_CC} ${D2U_CFLAGS} \$PREFIX_FLAGS -I'${SOURCE_PATH}' -DVER_REVISION='\"7.5.2\"' -DVER_DATE='\"2024-01-22\"' \
            -DDEBUG=0 -UD2U_UNIFILE \
            -c '${SOURCE_PATH}/common.c' -o common.o

        # Pack into raw archive
        ar rcs libd2u_raw.a dos2unix.o querycp.o common.o

        # Combine into one relocatable object
        ld -r --whole-archive libd2u_raw.a -o d2u_combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive libd2u_raw.a -o d2u_combined.o
        llvm-objcopy --wildcard --keep-global-symbol='*_main' d2u_combined.o

        # Package into final archive
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libdos2unix.a' d2u_combined.o
    "
    WORKING_DIRECTORY "${D2U_BUILD_DIR}"
    LOGNAME "build-${TARGET_TRIPLET}"
)

busyq_finalize_port(COPYRIGHT "${SOURCE_PATH}/COPYING.txt")
