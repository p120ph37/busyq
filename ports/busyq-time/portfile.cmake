# busyq-time portfile - uses Alpine-synced source and patches
include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_alpine_helpers.cmake")

busyq_alpine_source(
    PORT_DIR "${CMAKE_CURRENT_LIST_DIR}"
    OUT_SOURCE_PATH SOURCE_PATH
)

# busyq-specific fix: GNU time 1.9 doesn't include <string.h> in resuse.c,
# causing implicit function declaration errors with modern clang.
set(_resuse "${SOURCE_PATH}/src/resuse.c")
if(EXISTS "${_resuse}")
    file(READ "${_resuse}" _content)
    if(NOT _content MATCHES "#include <string\\.h>")
        string(REPLACE "#include \"config.h\"" "#include \"config.h\"\n#include <string.h>" _content "${_content}")
        file(WRITE "${_resuse}" "${_content}")
    endif()
endif()

# Detect toolchain flags
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

set(ENV{FORCE_UNSAFE_CONFIGURE} "1")

vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --disable-nls
)

vcpkg_build_make()

set(TIME_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# --- Symbol isolation ---
# GNU time embeds gnulib, so we need full symbol isolation.

file(GLOB TIME_OBJS "${TIME_BUILD_REL}/*.o")
file(GLOB TIME_SRC_OBJS "${TIME_BUILD_REL}/src/*.o")
file(GLOB TIME_LIB_OBJS "${TIME_BUILD_REL}/lib/*.o")
list(APPEND TIME_OBJS ${TIME_SRC_OBJS} ${TIME_LIB_OBJS})

if(NOT TIME_OBJS)
    message(FATAL_ERROR "No time object files found in ${TIME_BUILD_REL}")
endif()

vcpkg_execute_required_process(
    COMMAND ar rcs "${TIME_BUILD_REL}/libtime_raw.a" ${TIME_OBJS}
    WORKING_DIRECTORY "${TIME_BUILD_REL}"
    LOGNAME "ar-raw-${TARGET_TRIPLET}"
)

vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e

        ld -r --whole-archive libtime_raw.a -o time_combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive libtime_raw.a -o time_combined.o

        nm -u time_combined.o | sed 's/.* //' | sort -u > undef_syms.txt

        objcopy --prefix-symbols=time_ time_combined.o

        sed 's/.*/time_& &/' undef_syms.txt > redefine.map

        echo 'time_main time_main' >> redefine.map

        objcopy --redefine-syms=redefine.map time_combined.o

        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libtime.a' time_combined.o
    "
    WORKING_DIRECTORY "${TIME_BUILD_REL}"
    LOGNAME "symbol-isolate-${TARGET_TRIPLET}"
)

set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
