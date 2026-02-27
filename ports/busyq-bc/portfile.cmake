vcpkg_download_distfile(ARCHIVE
    URLS "https://ftpmirror.gnu.org/gnu/bc/bc-1.07.1.tar.gz"
         "https://mirrors.kernel.org/gnu/bc/bc-1.07.1.tar.gz"
         "https://ftp.gnu.org/gnu/bc/bc-1.07.1.tar.gz"
    FILENAME "bc-1.07.1.tar.gz"
    SHA512 0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
)

vcpkg_extract_source_archive(SOURCE_PATH ARCHIVE "${ARCHIVE}")

# Detect toolchain flags
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

set(BC_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(BC_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

set(ENV{FORCE_UNSAFE_CONFIGURE} "1")

vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --disable-nls
        --with-readline=no
)

vcpkg_build_make()

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

# Steps 2-7: Rename mains, combine, prefix, unprefix, rename entries
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e

        # Rename main in bc/main.o and dc/main.o before combining
        if [ -f bc/main.o ]; then
            objcopy --redefine-sym main=bc_main_orig bc/main.o
        fi
        if [ -f dc/main.o ]; then
            objcopy --redefine-sym main=dc_main_orig dc/main.o
        fi

        # Rebuild raw archive with renamed mains
        find bc dc lib -name '*.o' 2>/dev/null | xargs ar rcs libbc_raw.a

        # Combine into one relocatable object
        ld -r --whole-archive libbc_raw.a -o bc_combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive libbc_raw.a -o bc_combined.o

        # Record undefined symbols
        nm -u bc_combined.o | sed 's/.* //' | sort -u > undef_syms.txt

        # Prefix all symbols with bc_
        objcopy --prefix-symbols=bc_ bc_combined.o

        # Generate redefine map to unprefix external deps
        sed 's/.*/bc_& &/' undef_syms.txt > redefine.map

        # Map entry points: bc_bc_main_orig -> bc_main, bc_dc_main_orig -> dc_main
        echo 'bc_bc_main_orig bc_main' >> redefine.map
        echo 'bc_dc_main_orig dc_main' >> redefine.map

        objcopy --redefine-syms=redefine.map bc_combined.o

        # Package into final archive
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libbc.a' bc_combined.o
    "
    WORKING_DIRECTORY "${BC_BUILD_REL}"
    LOGNAME "symbol-isolate-${TARGET_TRIPLET}"
)

set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
