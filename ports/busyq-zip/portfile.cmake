# busyq-zip portfile - Info-ZIP zip 3.0 and unzip 6.0
# Uses Alpine-synced source and patches (6 for zip, 30 for unzip including CVE fixes)

include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_alpine_helpers.cmake")

# --- Download and patch both packages ---

busyq_alpine_source(
    PORT_DIR "${CMAKE_CURRENT_LIST_DIR}"
    SUBDIR zip
    OUT_SOURCE_PATH ZIP_SOURCE_PATH
    USE_PATCH_CMD
)

busyq_alpine_source(
    PORT_DIR "${CMAKE_CURRENT_LIST_DIR}"
    SUBDIR unzip
    OUT_SOURCE_PATH UNZIP_SOURCE_PATH
    EXTRA_URLS "https://downloads.sourceforge.net/infozip/unzip60.tar.gz"
    USE_PATCH_CMD
)

# Detect toolchain flags (CC, CFLAGS with LTO/optimization)
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

set(ZIP_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(ZIP_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# ============================================================
# Build zip 3.0
# ============================================================
# Alpine's patches fix unix/configure to respect LDFLAGS, handle PIC detection,
# and work with modern compilers. Use the `generic` target which runs configure.
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e
        make -f unix/Makefile \
            LOCAL_ZIP='${ZIP_CFLAGS}' \
            prefix=/usr \
            generic \
            -j1
    "
    WORKING_DIRECTORY "${ZIP_SOURCE_PATH}"
    LOGNAME "compile-zip-${TARGET_TRIPLET}"
)

# --- Symbol isolation for zip ---
set(ZIP_BUILD_DIR "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel-zip")
file(MAKE_DIRECTORY "${ZIP_BUILD_DIR}")

vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e

        find '${ZIP_SOURCE_PATH}' -name '*.o' ! -path '*/test/*' > zip_objs.txt

        ar rcs libzip_raw.a \$(cat zip_objs.txt)

        ld -r --whole-archive libzip_raw.a -o zip_combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive libzip_raw.a -o zip_combined.o

        nm -u zip_combined.o | sed 's/.* //' | sort -u > undef_syms.txt

        objcopy --prefix-symbols=zip_ zip_combined.o

        sed 's/.*/zip_& &/' undef_syms.txt > redefine.map

        echo 'zip_main zip_main' >> redefine.map

        objcopy --redefine-syms=redefine.map zip_combined.o

        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libzip.a' zip_combined.o
    "
    WORKING_DIRECTORY "${ZIP_BUILD_DIR}"
    LOGNAME "symbol-isolate-zip-${TARGET_TRIPLET}"
)

# ============================================================
# Build unzip 6.0
# ============================================================
# Build using Alpine's approach: manual defines + direct Makefile target.
# Alpine's 30 patches fix CVEs, format-security, heap overflows, zipbombs, etc.
# Alpine defines for unzip (from APKBUILD)
string(JOIN " " UNZIP_DEFINES
    -DACORN_FTYPE_NFS
    -DWILD_STOP_AT_DIR
    -DLARGE_FILE_SUPPORT
    -DUNICODE_SUPPORT
    -DUNICODE_WCHAR
    -DUTF8_MAYBE_NATIVE
    -DNO_LCHMOD
    -DDATE_FORMAT=DF_YMD
    -DNOMEMCPY
    -DNO_WORKING_ISPRINT
)

vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e
        make -f unix/Makefile \
            LF2='' \
            CF='${ZIP_CFLAGS} -I. ${UNZIP_DEFINES}' \
            prefix=/usr \
            unzips \
            -j1
    "
    WORKING_DIRECTORY "${UNZIP_SOURCE_PATH}"
    LOGNAME "compile-unzip-${TARGET_TRIPLET}"
)

# --- Symbol isolation for unzip ---
set(UNZIP_BUILD_DIR "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel-unzip")
file(MAKE_DIRECTORY "${UNZIP_BUILD_DIR}")

vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e

        find '${UNZIP_SOURCE_PATH}' -name '*.o' ! -path '*/test/*' > unzip_objs.txt

        ar rcs libunzip_raw.a \$(cat unzip_objs.txt)

        ld -r --whole-archive libunzip_raw.a -o unzip_combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive libunzip_raw.a -o unzip_combined.o

        nm -u unzip_combined.o | sed 's/.* //' | sort -u > undef_syms.txt

        objcopy --prefix-symbols=unzip_ unzip_combined.o

        sed 's/.*/unzip_& &/' undef_syms.txt > redefine.map

        echo 'unzip_main unzip_main' >> redefine.map

        objcopy --redefine-syms=redefine.map unzip_combined.o

        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libunzip.a' unzip_combined.o
    "
    WORKING_DIRECTORY "${UNZIP_BUILD_DIR}"
    LOGNAME "symbol-isolate-unzip-${TARGET_TRIPLET}"
)

set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

vcpkg_install_copyright(FILE_LIST "${ZIP_SOURCE_PATH}/LICENSE")
