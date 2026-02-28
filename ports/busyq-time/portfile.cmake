# busyq-time portfile - uses Alpine-synced source and patches
include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_alpine_helpers.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_symbol_helpers.cmake")

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

# Only build release (debug artifacts are unused)
set(VCPKG_BUILD_TYPE release)

# --- Generate compile-time symbol prefix header (LTO-safe) ---
set(_prefix_h "${SOURCE_PATH}/time_prefix.h")
busyq_gen_prefix_header(time "${_prefix_h}")

set(ENV{FORCE_UNSAFE_CONFIGURE} "1")

# Rename main() at source level (LTO-safe — do NOT use -Dmain in CPPFLAGS,
# it breaks autotools helper programs)
busyq_rename_main(time
    "${SOURCE_PATH}/src/time.c"
    "${SOURCE_PATH}/time.c"
)

vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --disable-nls
)

vcpkg_build_make(OPTIONS "CPPFLAGS=-include ${_prefix_h}")

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
    COMMAND ar rcs "${TIME_BUILD_REL}/lib_raw.a" ${TIME_OBJS}
    WORKING_DIRECTORY "${TIME_BUILD_REL}"
    LOGNAME "ar-raw-${TARGET_TRIPLET}"
)

# Combine objects and package (no objcopy — compile-time prefix preserves bitcode)
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e
        ld -r --whole-archive lib_raw.a -o combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive lib_raw.a -o combined.o
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libtime.a' combined.o
    "
    WORKING_DIRECTORY "${TIME_BUILD_REL}"
    LOGNAME "combine-${TARGET_TRIPLET}"
)

set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
