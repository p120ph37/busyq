# busyq-psmisc portfile - uses Alpine-synced source and patches
include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_alpine_helpers.cmake")

busyq_alpine_source(
    PORT_DIR "${CMAKE_CURRENT_LIST_DIR}"
    OUT_SOURCE_PATH SOURCE_PATH
)

# Detect toolchain flags
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

set(ENV{FORCE_UNSAFE_CONFIGURE} "1")

# vcpkg builds ncurses as libncursesw.a (wide-char), but psmisc's configure
# checks for -ltinfo / -lncurses / -ltermcap via AC_CHECK_LIB. Create
# compatibility symlinks so the linker check succeeds.
foreach(_libdir "${CURRENT_INSTALLED_DIR}/lib" "${CURRENT_INSTALLED_DIR}/debug/lib")
    if(EXISTS "${_libdir}/libncursesw.a" AND NOT EXISTS "${_libdir}/libncurses.a")
        file(CREATE_LINK "${_libdir}/libncursesw.a" "${_libdir}/libncurses.a" SYMBOLIC)
    endif()
    if(EXISTS "${_libdir}/libncursesw.a" AND NOT EXISTS "${_libdir}/libtinfo.a")
        file(CREATE_LINK "${_libdir}/libncursesw.a" "${_libdir}/libtinfo.a" SYMBOLIC)
    endif()
endforeach()

vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --disable-nls
        --without-selinux
)

vcpkg_build_make()

set(PSMISC_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# --- Symbol isolation ---
# psmisc has three separate tool binaries (killall, fuser, pstree), each with
# its own main(). Strategy: rename each main → <basename>_main_orig, combine,
# prefix all symbols, unprefix externals, rename entries to <tool>_main.

file(GLOB_RECURSE PSMISC_OBJS "${PSMISC_BUILD_REL}/src/*.o")
list(FILTER PSMISC_OBJS EXCLUDE REGEX "/(tests|testsuite|man|doc)/")

if(NOT PSMISC_OBJS)
    message(FATAL_ERROR "No psmisc object files found in ${PSMISC_BUILD_REL}")
endif()

vcpkg_execute_required_process(
    COMMAND ar rcs "${PSMISC_BUILD_REL}/libpsmisc_raw.a" ${PSMISC_OBJS}
    WORKING_DIRECTORY "${PSMISC_BUILD_REL}"
    LOGNAME "ar-raw-${TARGET_TRIPLET}"
)

vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e

        for obj in src/*.o
do
            [ -f \"\$obj\" ] || continue
            if nm \"\$obj\" 2>/dev/null | grep -q ' T main$'
then
                bn=\$(basename \"\$obj\" .o)
                objcopy --redefine-sym main=\${bn}_main_orig \"\$obj\"
            fi
        done

        find src/ -name '*.o' ! -path '*/tests/*' ! -path '*/testsuite/*' 2>/dev/null | sort > obj_list.txt
        ar rcs libpsmisc_raw.a \$(cat obj_list.txt) 2>/dev/null || true

        ld -r --whole-archive libpsmisc_raw.a -o psmisc_combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive libpsmisc_raw.a -o psmisc_combined.o

        nm -u psmisc_combined.o | sed 's/.* //' | sort -u > undef_syms.txt

        objcopy --prefix-symbols=psmisc_ psmisc_combined.o

        sed 's/.*/psmisc_& &/' undef_syms.txt > redefine.map

        nm psmisc_combined.o 2>/dev/null | grep '_main_orig' | sed 's/.* //' | while read sym
do
            tool=\$(echo \"\$sym\" | sed 's/^psmisc_//; s/_main_orig$//')
            echo \"\$sym \${tool}_main\"
        done >> redefine.map

        objcopy --redefine-syms=redefine.map psmisc_combined.o

        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libpsmisc.a' psmisc_combined.o
    "
    WORKING_DIRECTORY "${PSMISC_BUILD_REL}"
    LOGNAME "symbol-isolate-${TARGET_TRIPLET}"
)

set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
