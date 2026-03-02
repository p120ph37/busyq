# busyq-xxd: xxd hex dump tool from the vim source tree
#
# xxd is a standalone single-file tool (src/xxd/xxd.c) from vim.
# Alpine packages it as a separate "xxd" subpackage of vim.
# No symbol isolation needed -- no gnulib, no symbol collisions.

include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_alpine_helpers.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_symbol_helpers.cmake")

busyq_alpine_source(
    PORT_DIR "${CMAKE_CURRENT_LIST_DIR}"
    OUT_SOURCE_PATH SOURCE_PATH
)

# Detect toolchain flags
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

set(VCPKG_BUILD_TYPE release)

set(XXD_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(XXD_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

set(XXD_BUILD_DIR "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")
file(MAKE_DIRECTORY "${XXD_BUILD_DIR}")
file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e
        '${XXD_CC}' ${XXD_CFLAGS} \
            -DUNIX \
            -Dmain=xxd_main \
            -c '${SOURCE_PATH}/src/xxd/xxd.c' \
            -o xxd.o
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libxxd.a' xxd.o
    "
    WORKING_DIRECTORY "${XXD_BUILD_DIR}"
    LOGNAME "build-xxd-${TARGET_TRIPLET}"
)

busyq_finalize_port(COPYRIGHT "${SOURCE_PATH}/LICENSE")
