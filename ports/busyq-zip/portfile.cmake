# Info-ZIP: zip 3.0 and unzip 6.0
# Two separate upstream packages, built into libzip.a and libunzip.a

# --- Download both archives ---
vcpkg_download_distfile(ZIP_ARCHIVE
    URLS "https://downloads.sourceforge.net/infozip/zip30.tar.gz"
    FILENAME "zip30.tar.gz"
    SHA512 0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
)

vcpkg_download_distfile(UNZIP_ARCHIVE
    URLS "https://downloads.sourceforge.net/infozip/unzip60.tar.gz"
    FILENAME "unzip60.tar.gz"
    SHA512 0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
)

vcpkg_extract_source_archive(ZIP_SOURCE_PATH ARCHIVE "${ZIP_ARCHIVE}")
vcpkg_extract_source_archive(UNZIP_SOURCE_PATH ARCHIVE "${UNZIP_ARCHIVE}")

# Detect toolchain flags (CC, CFLAGS with LTO/optimization)
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

set(ZIP_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(ZIP_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# ============================================================
# Build zip 3.0
# ============================================================
set(ZIP_BUILD_DIR "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel-zip")
file(MAKE_DIRECTORY "${ZIP_BUILD_DIR}")

# Build using the unix Makefile
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e
        make -f unix/Makefile generic \
            CC='${ZIP_CC}' \
            CFLAGS='${ZIP_CFLAGS} -DUNIX -D_FILE_OFFSET_BITS=64' \
            -j1
    "
    WORKING_DIRECTORY "${ZIP_SOURCE_PATH}"
    LOGNAME "compile-zip-${TARGET_TRIPLET}"
)

# --- Symbol isolation for zip ---
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e

        # Collect all .o files from zip build
        find '${ZIP_SOURCE_PATH}' -name '*.o' ! -path '*/test/*' > zip_objs.txt

        # Pack into temporary archive
        ar rcs libzip_raw.a \$(cat zip_objs.txt)

        # Combine all objects into one relocatable .o
        ld -r --whole-archive libzip_raw.a -o zip_combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive libzip_raw.a -o zip_combined.o

        # Record undefined symbols (external deps: libc, etc.)
        nm -u zip_combined.o | sed 's/.* //' | sort -u > undef_syms.txt

        # Prefix all symbols with zip_
        objcopy --prefix-symbols=zip_ zip_combined.o

        # Generate redefine map to unprefix external deps
        sed 's/.*/zip_& &/' undef_syms.txt > redefine.map

        # Rename zip_main -> zip_main (entry point)
        # After prefix, main becomes zip_main which is already the desired name
        echo 'zip_main zip_main' >> redefine.map

        objcopy --redefine-syms=redefine.map zip_combined.o

        # Package into final archive
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libzip.a' zip_combined.o
    "
    WORKING_DIRECTORY "${ZIP_BUILD_DIR}"
    LOGNAME "symbol-isolate-zip-${TARGET_TRIPLET}"
)

# ============================================================
# Build unzip 6.0
# ============================================================
set(UNZIP_BUILD_DIR "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel-unzip")
file(MAKE_DIRECTORY "${UNZIP_BUILD_DIR}")

# Build using the unix Makefile
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e
        make -f unix/Makefile generic \
            CC='${ZIP_CC}' \
            CF='${ZIP_CFLAGS} -DUNIX -D_FILE_OFFSET_BITS=64 -I.' \
            -j1
    "
    WORKING_DIRECTORY "${UNZIP_SOURCE_PATH}"
    LOGNAME "compile-unzip-${TARGET_TRIPLET}"
)

# --- Symbol isolation for unzip ---
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e

        # Collect all .o files from unzip build
        find '${UNZIP_SOURCE_PATH}' -name '*.o' ! -path '*/test/*' > unzip_objs.txt

        # Pack into temporary archive
        ar rcs libunzip_raw.a \$(cat unzip_objs.txt)

        # Combine all objects into one relocatable .o
        ld -r --whole-archive libunzip_raw.a -o unzip_combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive libunzip_raw.a -o unzip_combined.o

        # Record undefined symbols (external deps: libc, etc.)
        nm -u unzip_combined.o | sed 's/.* //' | sort -u > undef_syms.txt

        # Prefix all symbols with unzip_
        objcopy --prefix-symbols=unzip_ unzip_combined.o

        # Generate redefine map to unprefix external deps
        sed 's/.*/unzip_& &/' undef_syms.txt > redefine.map

        # Rename unzip_main -> unzip_main (entry point)
        # After prefix, main becomes unzip_main which is already the desired name
        echo 'unzip_main unzip_main' >> redefine.map

        objcopy --redefine-syms=redefine.map unzip_combined.o

        # Package into final archive
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libunzip.a' unzip_combined.o
    "
    WORKING_DIRECTORY "${UNZIP_BUILD_DIR}"
    LOGNAME "symbol-isolate-unzip-${TARGET_TRIPLET}"
)

# Suppress vcpkg post-build warnings
set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

# Install copyright — zip and unzip both use the Info-ZIP license
vcpkg_install_copyright(FILE_LIST "${ZIP_SOURCE_PATH}/LICENSE")
