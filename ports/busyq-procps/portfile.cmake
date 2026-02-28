# busyq-procps portfile - uses Alpine-synced source and patches
#
# Alpine patches applied:
#   disable-test_pids-check.patch - Skip PID tests (only affects `make check`)
#
# Version: 4.0.5 (synced from Alpine 3.23-stable)

include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_alpine_helpers.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_symbol_helpers.cmake")

busyq_alpine_source(
    PORT_DIR "${CMAKE_CURRENT_LIST_DIR}"
    OUT_SOURCE_PATH SOURCE_PATH
)

# Detect toolchain flags before autotools claims the build directory
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

# --- Generate compile-time symbol prefix header (LTO-safe) ---
set(_prefix_h "${SOURCE_PATH}/procps_prefix.h")
busyq_gen_prefix_header(procps "${_prefix_h}")

set(ENV{FORCE_UNSAFE_CONFIGURE} "1")

# Alpine's disable-test_pids-check.patch touches Makefile.am for tests only.
# We never run `make check`, so autoreconf is not needed. Touch Makefile.in
# to prevent automake from triggering a rebuild during `make`.
file(GLOB_RECURSE _makefiles "${SOURCE_PATH}/Makefile.in")
foreach(_mf ${_makefiles})
    file(TOUCH "${_mf}")
endforeach()

vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --disable-nls
        --disable-shared
        --enable-static
        --without-systemd
        --disable-kill
        --enable-watch
)

vcpkg_build_make(OPTIONS "CPPFLAGS=-include ${_prefix_h}")

set(PROCPS_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# --- Symbol isolation ---
# procps-ng has multiple tool binaries each with their own main(), plus a
# shared libprocps library. Strategy:
#
# 1. Collect all .o files from library and tool sources
# 2. For each tool .o that defines main(), rename main → <basename>_main_orig
# 3. Combine into one relocatable object with ld -r
# 4. Record undefined symbols (external deps: libc, ncurses, etc.)
# 5. Prefix ALL symbols with procps_
# 6. Unprefix external deps so libc/ncurses calls work
# 7. Rename procps_<tool>_main_orig → <tool>_main for each tool
# 8. Package into libprocps.a

file(GLOB_RECURSE PROCPS_OBJS
    "${PROCPS_BUILD_REL}/src/*.o"
    "${PROCPS_BUILD_REL}/library/*.o"
    "${PROCPS_BUILD_REL}/local/*.o"
    "${PROCPS_BUILD_REL}/lib/*.o"
)
list(FILTER PROCPS_OBJS EXCLUDE REGEX "/(tests|testsuite|man|doc)/")

if(NOT PROCPS_OBJS)
    message(FATAL_ERROR "No procps-ng object files found in ${PROCPS_BUILD_REL}")
endif()

vcpkg_execute_required_process(
    COMMAND ar rcs "${PROCPS_BUILD_REL}/libprocps_raw.a" ${PROCPS_OBJS}
    WORKING_DIRECTORY "${PROCPS_BUILD_REL}"
    LOGNAME "ar-raw-${TARGET_TRIPLET}"
)

# Rename mains and combine (no --prefix-symbols — compile-time prefix preserves bitcode)
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e

        # Rename main in each tool's object file dynamically
        for obj in \$(find src/ -name '*.o' ! -path '*/tests/*' ! -path '*/testsuite/*' 2>/dev/null); do
            if nm \"\$obj\" 2>/dev/null | grep -q ' T main$'; then
                tool=\$(basename \"\$obj\" .o)
                objcopy --redefine-sym main=\"\${tool}_main\" \"\$obj\"
            fi
        done

        find src/ library/ local/ lib/ -name '*.o' ! -path '*/tests/*' ! -path '*/testsuite/*' 2>/dev/null | sort > obj_list.txt
        ar rcs libprocps_raw.a \$(cat obj_list.txt) 2>/dev/null || true

        # Combine all objects into one relocatable .o
        ld -r --whole-archive libprocps_raw.a -o combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive libprocps_raw.a -o combined.o

        # Fix known entry point mismatches (file basename != tool name)
        # ps: main() is in src/ps/display.c, not src/ps/ps.c
        if nm combined.o 2>/dev/null | grep -q ' T display_main'; then
            objcopy --redefine-sym display_main=ps_main combined.o
        fi

        # Package into final archive
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libprocps.a' combined.o
    "
    WORKING_DIRECTORY "${PROCPS_BUILD_REL}"
    LOGNAME "combine-${TARGET_TRIPLET}"
)

set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
