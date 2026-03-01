# strings is a minimal standalone implementation — no source download needed.
# The source file is shipped directly in the port directory.

include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_symbol_helpers.cmake")

# Detect toolchain flags
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

# Only build release (debug artifacts are unused)
set(VCPKG_BUILD_TYPE release)

set(STRINGS_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(STRINGS_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# Compile strings.c with -Dmain=strings_main directly.
# No symbol isolation needed — this is a single self-contained source file
# with no gnulib or other conflicting symbols.
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e
        ${STRINGS_CC} ${STRINGS_CFLAGS} -Dmain=strings_main -c '${CMAKE_CURRENT_LIST_DIR}/strings.c' -o strings.o
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libstrings.a' strings.o
    "
    WORKING_DIRECTORY "${CURRENT_BUILDTREES_DIR}"
    LOGNAME "build-${TARGET_TRIPLET}"
)

# No upstream source, use a generated copyright notice
file(WRITE "${CURRENT_PACKAGES_DIR}/share/${PORT}/copyright"
    "Minimal strings implementation for busyq.\nLicense: MIT\n")

busyq_finalize_port(COPYRIGHT "${CURRENT_PACKAGES_DIR}/share/${PORT}/copyright")
