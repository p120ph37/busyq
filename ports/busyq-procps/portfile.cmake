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

# Only build release (debug artifacts are unused)
set(VCPKG_BUILD_TYPE release)

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

# Rename main() after the build — doing it before would break the link step
# Most tools: src/<tool>.c, special cases: src/ps/display.c, src/top/top.c
set(_procps_main_renames
    "free:src/free.c"
    "pgrep:src/pgrep.c"
    "pidof:src/pidof.c"
    "pmap:src/pmap.c"
    "pwdx:src/pwdx.c"
    "watch:src/watch.c"
    "sysctl:src/sysctl.c"
    "vmstat:src/vmstat.c"
    "uptime:src/uptime.c"
    "w:src/w.c"
    "tload:src/tload.c"
    "slabtop:src/slabtop.c"
    "top:src/top/top.c"
    "ps:src/ps/display.c"
)
foreach(_entry ${_procps_main_renames})
    string(REPLACE ":" ";" _parts "${_entry}")
    list(GET _parts 0 _tool)
    list(GET _parts 1 _file)
    busyq_post_build_rename_main(${_tool} "${_prefix_h}" "${SOURCE_PATH}/${_file}")
endforeach()

set(PROCPS_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

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

busyq_package_objects(libprocps.a "${PROCPS_BUILD_REL}" OBJECTS ${PROCPS_OBJS})

busyq_finalize_port()
