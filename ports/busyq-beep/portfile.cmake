vcpkg_download_distfile(ARCHIVE
    URLS "https://github.com/spkr-beep/beep/archive/refs/tags/v1.4.12.tar.gz"
    FILENAME "beep-1.4.12.tar.gz"
    SHA512 0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
)

vcpkg_extract_source_archive(SOURCE_PATH ARCHIVE "${ARCHIVE}")

# Detect toolchain flags
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

set(BEEP_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(BEEP_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# beep is a single C file — compile manually with -Dmain=beep_main.
# No gnulib, no symbol isolation needed.
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e
        ${BEEP_CC} ${BEEP_CFLAGS} -Dmain=beep_main -c '${SOURCE_PATH}/beep.c' -o beep.o
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libbeep.a' beep.o
    "
    WORKING_DIRECTORY "${CURRENT_BUILDTREES_DIR}"
    LOGNAME "build-${TARGET_TRIPLET}"
)

set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
