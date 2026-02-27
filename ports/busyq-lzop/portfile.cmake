include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_alpine_helpers.cmake")

busyq_alpine_source(
    PORT_DIR "${CMAKE_CURRENT_LIST_DIR}"
    OUT_SOURCE_PATH SOURCE_PATH
)

# Detect toolchain flags (CC, CFLAGS with LTO/optimization)
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

set(LZOP_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(LZOP_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

set(ENV{FORCE_UNSAFE_CONFIGURE} "1")

# lzop depends on lzo2 library — find its headers and library from vcpkg
set(LZO_INCLUDE "${CURRENT_INSTALLED_DIR}/include")
set(LZO_LIB "${CURRENT_INSTALLED_DIR}/lib")

vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --disable-nls
        "CPPFLAGS=-I${LZO_INCLUDE}"
        "LDFLAGS=-L${LZO_LIB}"
)

vcpkg_build_make()

set(LZOP_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# --- Symbol isolation ---
# Collect all .o files from lzop build
file(GLOB_RECURSE LZOP_OBJS
    "${LZOP_BUILD_REL}/src/*.o"
)
list(FILTER LZOP_OBJS EXCLUDE REGEX "/(tests)/")

if(NOT LZOP_OBJS)
    message(FATAL_ERROR "No lzop object files found in ${LZOP_BUILD_REL}")
endif()

# Pack into temporary archive
vcpkg_execute_required_process(
    COMMAND ar rcs "${LZOP_BUILD_REL}/liblzop_raw.a" ${LZOP_OBJS}
    WORKING_DIRECTORY "${LZOP_BUILD_REL}"
    LOGNAME "ar-raw-${TARGET_TRIPLET}"
)

# Combine, prefix, unprefix, rename
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e

        # Combine all objects into one relocatable .o
        ld -r --whole-archive liblzop_raw.a -o lzop_combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive liblzop_raw.a -o lzop_combined.o

        # Record undefined symbols (external deps: libc, lzo2, etc.)
        nm -u lzop_combined.o | sed 's/.* //' | sort -u > undef_syms.txt

        # Prefix all symbols with lzop_
        objcopy --prefix-symbols=lzop_ lzop_combined.o

        # Generate redefine map to unprefix external deps
        sed 's/.*/lzop_& &/' undef_syms.txt > redefine.map

        # Rename lzop_main -> lzop_main (entry point)
        # After prefix, main becomes lzop_main which is already the desired name
        echo 'lzop_main lzop_main' >> redefine.map

        objcopy --redefine-syms=redefine.map lzop_combined.o

        # Package into final archive
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/liblzop.a' lzop_combined.o
    "
    WORKING_DIRECTORY "${LZOP_BUILD_REL}"
    LOGNAME "symbol-isolate-${TARGET_TRIPLET}"
)

# Suppress vcpkg post-build warnings
set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

# Install copyright
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
