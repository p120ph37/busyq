# Detect toolchain flags
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

set(TSET_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(TSET_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

# Find ncurses headers from vcpkg
set(NCURSES_INCLUDE "${CURRENT_INSTALLED_DIR}/include/ncursesw")
if(NOT EXISTS "${NCURSES_INCLUDE}")
    set(NCURSES_INCLUDE "${CURRENT_INSTALLED_DIR}/include")
endif()

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# Compile our minimal reset.c using the public ncurses API.
# reset and tset are registered as applets that call tset_main().
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e
        ${TSET_CC} ${TSET_CFLAGS} \
            -I'${NCURSES_INCLUDE}' \
            -I'${CURRENT_INSTALLED_DIR}/include' \
            -c '${CMAKE_CURRENT_LIST_DIR}/reset.c' -o tset.o
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libtset.a' tset.o
    "
    WORKING_DIRECTORY "${CURRENT_BUILDTREES_DIR}"
    LOGNAME "build-${TARGET_TRIPLET}"
)

set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

file(WRITE "${CURRENT_PACKAGES_DIR}/share/${PORT}/copyright" "Part of busyq project - reset/tset terminal utility\n")
