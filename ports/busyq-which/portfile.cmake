vcpkg_download_distfile(ARCHIVE
    URLS "https://ftpmirror.gnu.org/gnu/which/which-2.21.tar.gz"
         "https://mirrors.kernel.org/gnu/which/which-2.21.tar.gz"
         "https://ftp.gnu.org/gnu/which/which-2.21.tar.gz"
    FILENAME "which-2.21.tar.gz"
    SHA512 d2f04a5c5291f2d7d1226982da7cf999d36cfe24d3f7bda145508efcfb359511251d3c68b860c0ddcedd66b15a0587b648a35ab6d1f173707565305c506dfc61
)

vcpkg_extract_source_archive(SOURCE_PATH ARCHIVE "${ARCHIVE}")

# Detect toolchain flags
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

set(WHICH_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(WHICH_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

set(ENV{FORCE_UNSAFE_CONFIGURE} "1")

vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --disable-nls
)

vcpkg_build_make()

set(WHICH_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# --- Symbol isolation ---
# GNU which is simple but may embed gnulib, so apply full isolation.

# Step 1: Collect object files
file(GLOB WHICH_OBJS "${WHICH_BUILD_REL}/*.o")
file(GLOB WHICH_LIB_OBJS "${WHICH_BUILD_REL}/lib/*.o")
list(APPEND WHICH_OBJS ${WHICH_LIB_OBJS})

if(NOT WHICH_OBJS)
    message(FATAL_ERROR "No which object files found in ${WHICH_BUILD_REL}")
endif()

# Step 1a: Pack into temporary archive
vcpkg_execute_required_process(
    COMMAND ar rcs "${WHICH_BUILD_REL}/libwhich_raw.a" ${WHICH_OBJS}
    WORKING_DIRECTORY "${WHICH_BUILD_REL}"
    LOGNAME "ar-raw-${TARGET_TRIPLET}"
)

# Steps 2-7: Combine, prefix, unprefix, rename
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e

        # Combine into one relocatable object
        ld -r --whole-archive libwhich_raw.a -o which_combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive libwhich_raw.a -o which_combined.o

        # Record undefined symbols
        nm -u which_combined.o | sed 's/.* //' | sort -u > undef_syms.txt

        # Prefix all symbols with which_
        objcopy --prefix-symbols=which_ which_combined.o

        # Generate redefine map to unprefix external deps
        sed 's/.*/which_& &/' undef_syms.txt > redefine.map

        # Rename which_main -> which_main (entry point)
        echo 'which_main which_main' >> redefine.map

        objcopy --redefine-syms=redefine.map which_combined.o

        # Package into final archive
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libwhich.a' which_combined.o
    "
    WORKING_DIRECTORY "${WHICH_BUILD_REL}"
    LOGNAME "symbol-isolate-${TARGET_TRIPLET}"
)

set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
