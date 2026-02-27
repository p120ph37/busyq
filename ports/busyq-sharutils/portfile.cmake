vcpkg_download_distfile(ARCHIVE
    URLS "https://ftpmirror.gnu.org/gnu/sharutils/sharutils-4.15.2.tar.xz"
         "https://mirrors.kernel.org/gnu/sharutils/sharutils-4.15.2.tar.xz"
         "https://ftp.gnu.org/gnu/sharutils/sharutils-4.15.2.tar.xz"
    FILENAME "sharutils-4.15.2.tar.xz"
    SHA512 80d0b804a0617e11e5c23dc0d59b218bbf93e40aaf5e9a5401a18ef9cb700390aab711e2b2e2f26c8fd5b8ef99a91d3405e01d02cadabcba7639979314e59f8d
)

vcpkg_extract_source_archive(SOURCE_PATH ARCHIVE "${ARCHIVE}")

# Detect toolchain flags
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

set(SHAR_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(SHAR_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

set(ENV{FORCE_UNSAFE_CONFIGURE} "1")

# sharutils 4.15.2 needs two patches for modern clang:
# 1. NLS functions called without headers (add libintl.h)
# 2. program_name defined in both .h and .c without extern (use -fcommon)
foreach(_src shar.c unshar.c uuencode.c uudecode.c)
    set(_file "${SOURCE_PATH}/src/${_src}")
    if(EXISTS "${_file}")
        file(READ "${_file}" _content)
        if(NOT _content MATCHES "#include <libintl\\.h>")
            file(WRITE "${_file}" "#include <libintl.h>\n${_content}")
        endif()
    endif()
endforeach()

# Fix tentative definition of program_name in opts headers (missing extern)
foreach(_hdr shar-opts.h unshar-opts.h uuencode-opts.h uudecode-opts.h)
    set(_file "${SOURCE_PATH}/src/${_hdr}")
    if(EXISTS "${_file}")
        file(READ "${_file}" _content)
        string(REPLACE "char const * const program_name;" "extern char const * const program_name;" _content "${_content}")
        file(WRITE "${_file}" "${_content}")
    endif()
endforeach()

vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --disable-nls
)

vcpkg_build_make()

set(SHAR_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# --- Symbol isolation ---
# sharutils has uuencode and uudecode with separate main() functions.
# We must rename them before combining so we can expose both entry points.

# Step 1: Collect object files from src and lib subdirectories
file(GLOB SHAR_SRC_OBJS "${SHAR_BUILD_REL}/src/*.o")
file(GLOB SHAR_LIB_OBJS "${SHAR_BUILD_REL}/lib/*.o")

set(SHAR_ALL_OBJS ${SHAR_SRC_OBJS} ${SHAR_LIB_OBJS})

if(NOT SHAR_ALL_OBJS)
    message(FATAL_ERROR "No sharutils object files found in ${SHAR_BUILD_REL}")
endif()

# Step 1a: Pack into temporary archive
vcpkg_execute_required_process(
    COMMAND ar rcs "${SHAR_BUILD_REL}/libshar_raw.a" ${SHAR_ALL_OBJS}
    WORKING_DIRECTORY "${SHAR_BUILD_REL}"
    LOGNAME "ar-raw-${TARGET_TRIPLET}"
)

# Steps 2-7: Rename mains, combine, prefix, unprefix, rename entries
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e

        # Rename main in uuencode.o and uudecode.o before combining
        if [ -f src/uuencode.o ]
then
            objcopy --redefine-sym main=uuencode_main_orig src/uuencode.o
        fi
        if [ -f src/uudecode.o ]
then
            objcopy --redefine-sym main=uudecode_main_orig src/uudecode.o
        fi

        # Rebuild raw archive with renamed mains
        find src lib -name '*.o' 2>/dev/null | xargs ar rcs libshar_raw.a

        # Combine into one relocatable object
        ld -r --whole-archive libshar_raw.a -o shar_combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive libshar_raw.a -o shar_combined.o

        # Record undefined symbols
        nm -u shar_combined.o | sed 's/.* //' | sort -u > undef_syms.txt

        # Prefix all symbols with shar_
        objcopy --prefix-symbols=shar_ shar_combined.o

        # Generate redefine map to unprefix external deps
        sed 's/.*/shar_& &/' undef_syms.txt > redefine.map

        # Map entry points
        echo 'shar_uuencode_main_orig uuencode_main' >> redefine.map
        echo 'shar_uudecode_main_orig uudecode_main' >> redefine.map

        objcopy --redefine-syms=redefine.map shar_combined.o

        # Package into final archive
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libsharutils.a' shar_combined.o
    "
    WORKING_DIRECTORY "${SHAR_BUILD_REL}"
    LOGNAME "symbol-isolate-${TARGET_TRIPLET}"
)

set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
