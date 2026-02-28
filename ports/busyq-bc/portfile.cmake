# busyq-bc portfile - GNU bc and dc, uses Alpine-synced source
#
# Version: 1.08.2 (synced from Alpine 3.23-stable, zero patches)

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
set(_prefix_h "${SOURCE_PATH}/bc_prefix.h")
busyq_gen_prefix_header(bc "${_prefix_h}")

set(BC_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(BC_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

set(ENV{FORCE_UNSAFE_CONFIGURE} "1")

# Rename main() at source level for each tool (LTO-safe — objcopy can't
# rename symbols in LLVM bitcode objects)
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e
        for f in bc/main.c bc/bc.c; do
            if [ -f '${SOURCE_PATH}/'\"'\$f'\" ]; then
                sed -i '1i #define main bc_main' '${SOURCE_PATH}/'\"'\$f'\"
                break
            fi
        done
        for f in dc/main.c dc/dc.c; do
            if [ -f '${SOURCE_PATH}/'\"'\$f'\" ]; then
                sed -i '1i #define main dc_main' '${SOURCE_PATH}/'\"'\$f'\"
                break
            fi
        done
    "
    WORKING_DIRECTORY "${SOURCE_PATH}"
    LOGNAME "rename-mains-${TARGET_TRIPLET}"
)

vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --disable-nls
        --with-readline=no
)

vcpkg_build_make(OPTIONS "CPPFLAGS=-include ${_prefix_h}")

set(BC_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# --- Symbol isolation ---
# bc and dc have separate main() functions. We must rename them before
# combining so we can expose both bc_main and dc_main entry points.

# Step 1: Collect object files from bc and dc subdirectories
file(GLOB BC_BC_OBJS "${BC_BUILD_REL}/bc/*.o")
file(GLOB BC_DC_OBJS "${BC_BUILD_REL}/dc/*.o")
file(GLOB BC_LIB_OBJS "${BC_BUILD_REL}/lib/*.o")

set(BC_ALL_OBJS ${BC_BC_OBJS} ${BC_DC_OBJS} ${BC_LIB_OBJS})

if(NOT BC_ALL_OBJS)
    message(FATAL_ERROR "No bc object files found in ${BC_BUILD_REL}")
endif()

# Step 1a: Pack into temporary archive
vcpkg_execute_required_process(
    COMMAND ar rcs "${BC_BUILD_REL}/libbc_raw.a" ${BC_ALL_OBJS}
    WORKING_DIRECTORY "${BC_BUILD_REL}"
    LOGNAME "ar-raw-${TARGET_TRIPLET}"
)

# Combine objects and package (mains already renamed at source level)
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e

        # Combine all objects into one relocatable .o
        ld -r --whole-archive libbc_raw.a -o combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive libbc_raw.a -o combined.o

        # Package into final archive
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libbc.a' combined.o
    "
    WORKING_DIRECTORY "${BC_BUILD_REL}"
    LOGNAME "combine-${TARGET_TRIPLET}"
)

set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
