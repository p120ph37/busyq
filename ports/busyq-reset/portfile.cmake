vcpkg_download_distfile(ARCHIVE
    URLS "https://ftpmirror.gnu.org/gnu/ncurses/ncurses-6.5.tar.gz"
         "https://mirrors.kernel.org/gnu/ncurses/ncurses-6.5.tar.gz"
         "https://ftp.gnu.org/gnu/ncurses/ncurses-6.5.tar.gz"
    FILENAME "ncurses-6.5.tar.gz"
    SHA512 0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
)

vcpkg_extract_source_archive(SOURCE_PATH ARCHIVE "${ARCHIVE}")

# Detect toolchain flags
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

set(TSET_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(TSET_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

# Find ncurses headers and library from vcpkg
set(NCURSES_INCLUDE "${CURRENT_INSTALLED_DIR}/include/ncursesw")
if(NOT EXISTS "${NCURSES_INCLUDE}")
    set(NCURSES_INCLUDE "${CURRENT_INSTALLED_DIR}/include/ncurses")
endif()
if(NOT EXISTS "${NCURSES_INCLUDE}")
    set(NCURSES_INCLUDE "${CURRENT_INSTALLED_DIR}/include")
endif()

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# Compile just progs/tset.c from the ncurses source tree.
# tset and reset are the same program dispatching on argv[0].
# We compile with -Dmain=tset_main. No symbol isolation needed since
# tset.c is a standalone program that links against the ncurses library.
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e

        # tset.c needs some ncurses internal headers — set up include paths
        # to both the vcpkg-installed ncurses and the source tree
        ${TSET_CC} ${TSET_CFLAGS} \
            -Dmain=tset_main \
            -I'${NCURSES_INCLUDE}' \
            -I'${CURRENT_INSTALLED_DIR}/include' \
            -I'${SOURCE_PATH}/include' \
            -I'${SOURCE_PATH}/progs' \
            -DHAVE_UNISTD_H=1 \
            -DHAVE_TCGETATTR=1 \
            -DHAVE_SIZECHANGE=1 \
            -c '${SOURCE_PATH}/progs/tset.c' -o tset.o
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libtset.a' tset.o
    "
    WORKING_DIRECTORY "${CURRENT_BUILDTREES_DIR}"
    LOGNAME "build-${TARGET_TRIPLET}"
)

set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
