# busyq-procps portfile - uses Alpine-synced source and patches
#
# Alpine patches applied:
#   disable-test_pids-check.patch - Skip PID tests (only affects `make check`)
#
# Version: 4.0.5 (synced from Alpine 3.23-stable)

include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_alpine_helpers.cmake")

busyq_alpine_source(
    PORT_DIR "${CMAKE_CURRENT_LIST_DIR}"
    OUT_SOURCE_PATH SOURCE_PATH
)

# Detect toolchain flags before autotools claims the build directory
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

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

vcpkg_build_make()

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

vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e

        for obj in src/*.o src/*/*.o
do
            [ -f \"\$obj\" ] || continue
            if nm \"\$obj\" 2>/dev/null | grep -q ' T main$'
then
                bn=\$(basename \"\$obj\" .o)
                objcopy --redefine-sym main=\${bn}_main_orig \"\$obj\"
            fi
        done

        find src/ library/ local/ lib/ -name '*.o' ! -path '*/tests/*' ! -path '*/testsuite/*' 2>/dev/null | sort > obj_list.txt
        ar rcs libprocps_raw.a \$(cat obj_list.txt) 2>/dev/null || true

        ld -r --whole-archive libprocps_raw.a -o procps_combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive libprocps_raw.a -o procps_combined.o

        nm -u procps_combined.o | sed 's/.* //' | sort -u > undef_syms.txt

        objcopy --prefix-symbols=procps_ procps_combined.o

        sed 's/.*/procps_& &/' undef_syms.txt > redefine.map

        # Explicit tool name mapping (basename → applet name)
        # Some procps binaries have hyphenated names (top-top, watch-watch)
        # or differ from the applet name (display → ps, pgrep → also pkill)
        echo 'procps_display_main_orig ps_main' >> redefine.map
        echo 'procps_free_main_orig free_main' >> redefine.map
        echo 'procps_top-top_main_orig top_main' >> redefine.map
        echo 'procps_pgrep_main_orig pgrep_main' >> redefine.map
        echo 'procps_pidof_main_orig pidof_main' >> redefine.map
        echo 'procps_pmap_main_orig pmap_main' >> redefine.map
        echo 'procps_pwdx_main_orig pwdx_main' >> redefine.map
        echo 'procps_watch-watch_main_orig watch_main' >> redefine.map
        echo 'procps_sysctl_main_orig sysctl_main' >> redefine.map
        echo 'procps_vmstat_main_orig vmstat_main' >> redefine.map
        echo 'procps_uptime_main_orig uptime_main' >> redefine.map
        echo 'procps_w_main_orig w_main' >> redefine.map
        echo 'procps_tload_main_orig tload_main' >> redefine.map
        echo 'procps_slabtop-slabtop_main_orig slabtop_main' >> redefine.map
        echo 'procps_hugetop-hugetop_main_orig hugetop_main' >> redefine.map

        objcopy --redefine-syms=redefine.map procps_combined.o

        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libprocps.a' procps_combined.o
    "
    WORKING_DIRECTORY "${PROCPS_BUILD_REL}"
    LOGNAME "symbol-isolate-${TARGET_TRIPLET}"
)

set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
