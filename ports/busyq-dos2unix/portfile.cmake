include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_alpine_helpers.cmake")

busyq_alpine_source(
    PORT_DIR "${CMAKE_CURRENT_LIST_DIR}"
    OUT_SOURCE_PATH SOURCE_PATH
)

# Detect toolchain flags
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

set(D2U_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(D2U_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# --- Symbol isolation ---
# dos2unix and unix2dos are the same binary dispatching on argv[0].
# The main source files are dos2unix.c, querycp.c, common.c.
# We compile them manually and apply symbol isolation.

vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e

        # Compile key source files
        # dos2unix.c contains the main() that dispatches on argv[0]
        ${D2U_CC} ${D2U_CFLAGS} -I'${SOURCE_PATH}' -DVER_REVISION='\"7.5.2\"' -DVER_DATE='\"2024-01-22\"' \
            -DVER_AUTHOR='\"\"' -DDEBUG=0 -UD2U_UNIFILE \
            -c '${SOURCE_PATH}/dos2unix.c' -o dos2unix.o
        ${D2U_CC} ${D2U_CFLAGS} -I'${SOURCE_PATH}' -DVER_REVISION='\"7.5.2\"' -DVER_DATE='\"2024-01-22\"' \
            -DDEBUG=0 -UD2U_UNIFILE \
            -c '${SOURCE_PATH}/querycp.c' -o querycp.o
        ${D2U_CC} ${D2U_CFLAGS} -I'${SOURCE_PATH}' -DVER_REVISION='\"7.5.2\"' -DVER_DATE='\"2024-01-22\"' \
            -DDEBUG=0 -UD2U_UNIFILE \
            -c '${SOURCE_PATH}/common.c' -o common.o

        # Pack into raw archive
        ar rcs libd2u_raw.a dos2unix.o querycp.o common.o

        # Combine into one relocatable object
        ld -r --whole-archive libd2u_raw.a -o d2u_combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive libd2u_raw.a -o d2u_combined.o

        # Record undefined symbols
        nm -u d2u_combined.o | sed 's/.* //' | sort -u > undef_syms.txt

        # Prefix all symbols with d2u_
        objcopy --prefix-symbols=d2u_ d2u_combined.o

        # Generate redefine map to unprefix external deps
        sed 's/.*/d2u_& &/' undef_syms.txt > redefine.map

        # Map entry point: d2u_main -> dos2unix_main
        # (dos2unix dispatches on argv[0] for both dos2unix and unix2dos)
        echo 'd2u_main dos2unix_main' >> redefine.map

        objcopy --redefine-syms=redefine.map d2u_combined.o

        # Package into final archive
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libdos2unix.a' d2u_combined.o
    "
    WORKING_DIRECTORY "${CURRENT_BUILDTREES_DIR}"
    LOGNAME "build-${TARGET_TRIPLET}"
)

set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING.txt")
