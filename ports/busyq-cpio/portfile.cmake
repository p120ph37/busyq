include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_alpine_helpers.cmake")

busyq_alpine_source(
    PORT_DIR "${CMAKE_CURRENT_LIST_DIR}"
    OUT_SOURCE_PATH SOURCE_PATH
    USE_PATCH_CMD
)

# Detect toolchain flags (CC, CFLAGS with LTO/optimization)
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

set(CPIO_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(CPIO_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

set(ENV{FORCE_UNSAFE_CONFIGURE} "1")

vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --disable-nls
)

vcpkg_build_make()

set(CPIO_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# --- Symbol isolation ---
# Collect all .o files from cpio build
file(GLOB_RECURSE CPIO_OBJS
    "${CPIO_BUILD_REL}/src/*.o"
    "${CPIO_BUILD_REL}/lib/*.o"
    "${CPIO_BUILD_REL}/gnu/*.o"
)
list(FILTER CPIO_OBJS EXCLUDE REGEX "/(tests|gnulib-tests)/")

if(NOT CPIO_OBJS)
    message(FATAL_ERROR "No cpio object files found in ${CPIO_BUILD_REL}")
endif()

# Pack into temporary archive
vcpkg_execute_required_process(
    COMMAND ar rcs "${CPIO_BUILD_REL}/libcpio_raw.a" ${CPIO_OBJS}
    WORKING_DIRECTORY "${CPIO_BUILD_REL}"
    LOGNAME "ar-raw-${TARGET_TRIPLET}"
)

# Combine, prefix, unprefix, rename
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e

        # Combine all objects into one relocatable .o
        ld -r --whole-archive libcpio_raw.a -o cpio_combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive libcpio_raw.a -o cpio_combined.o

        # Record undefined symbols (external deps: libc, etc.)
        nm -u cpio_combined.o | sed 's/.* //' | sort -u > undef_syms.txt

        # Prefix all symbols with cpio_
        objcopy --prefix-symbols=cpio_ cpio_combined.o

        # Generate redefine map to unprefix external deps
        sed 's/.*/cpio_& &/' undef_syms.txt > redefine.map

        # Rename cpio_main -> cpio_main (entry point)
        echo 'cpio_main cpio_main' >> redefine.map

        objcopy --redefine-syms=redefine.map cpio_combined.o

        # Package into final archive
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libcpio.a' cpio_combined.o
    "
    WORKING_DIRECTORY "${CPIO_BUILD_REL}"
    LOGNAME "symbol-isolate-${TARGET_TRIPLET}"
)

# Suppress vcpkg post-build warnings
set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

# Install copyright
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
