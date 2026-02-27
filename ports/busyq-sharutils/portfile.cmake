# busyq-sharutils portfile - uses Alpine-synced source and patches
#
# Alpine patches applied:
#   format-security.patch                           - Format string security fixes
#   gcc-10.patch                                    - extern on program_name (was inline fix)
#   Backport-stdbool.m4-from-gnulib-devel-0-52.2.patch - gnulib m4 update
#   Port-getcwd.m4-to-ISO-C23.patch                 - getcwd detection for C23
#   Port-the-code-to-ISO-C23.patch                  - Function declarations for C23
#
# These patches touch .m4 files, so autoreconf is required after patching.

include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_alpine_helpers.cmake")

busyq_alpine_source(
    PORT_DIR "${CMAKE_CURRENT_LIST_DIR}"
    OUT_SOURCE_PATH SOURCE_PATH
)

# busyq-specific fix: with --disable-nls, bindtextdomain/textdomain are
# only defined as macros in gnulib's gettext.h. The source files call them
# without including that header. Add the include after Alpine patches.
foreach(_src shar.c unshar.c uuencode.c uudecode.c)
    set(_file "${SOURCE_PATH}/src/${_src}")
    if(EXISTS "${_file}")
        file(READ "${_file}" _content)
        if(NOT _content MATCHES "#include \"gettext\\.h\"")
            string(REGEX REPLACE "(#include \"[a-z]+-opts\\.h\")" "\\1\n#include \"gettext.h\"" _content "${_content}")
            file(WRITE "${_file}" "${_content}")
        endif()
    endif()
endforeach()

# Detect toolchain flags
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

set(ENV{FORCE_UNSAFE_CONFIGURE} "1")

# Alpine patches touch .m4 files; regenerate configure
vcpkg_execute_required_process(
    COMMAND autoreconf -vif
    WORKING_DIRECTORY "${SOURCE_PATH}"
    LOGNAME "autoreconf-${TARGET_TRIPLET}"
)

vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --disable-nls
        --disable-dependency-tracking
)

vcpkg_build_make()

set(SHAR_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# --- Symbol isolation ---
# sharutils has uuencode and uudecode with separate main() functions.
# We must rename them before combining so we can expose both entry points.

file(GLOB SHAR_SRC_OBJS "${SHAR_BUILD_REL}/src/*.o")
file(GLOB SHAR_LIB_OBJS "${SHAR_BUILD_REL}/lib/*.o")
file(GLOB SHAR_LIBOPTS_OBJS "${SHAR_BUILD_REL}/libopts/*.o")
set(SHAR_ALL_OBJS ${SHAR_SRC_OBJS} ${SHAR_LIB_OBJS} ${SHAR_LIBOPTS_OBJS})

if(NOT SHAR_ALL_OBJS)
    message(FATAL_ERROR "No sharutils object files found in ${SHAR_BUILD_REL}")
endif()

vcpkg_execute_required_process(
    COMMAND ar rcs "${SHAR_BUILD_REL}/libshar_raw.a" ${SHAR_ALL_OBJS}
    WORKING_DIRECTORY "${SHAR_BUILD_REL}"
    LOGNAME "ar-raw-${TARGET_TRIPLET}"
)

vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e

        # Rename main in uuencode.o and uudecode.o before combining
        if [ -f src/uuencode.o ]
then
            objcopy --redefine-sym main=uuencode_main_orig src/uuencode.o
        fi
        if [ -f src/uudecode.o ]
then
            objcopy --redefine-sym main=uudecode_main_orig src/uudecode.o
        fi

        # Rebuild raw archive with renamed mains
        find src lib libopts -name '*.o' 2>/dev/null | xargs ar rcs libshar_raw.a

        # Combine into one relocatable object
        ld -r --whole-archive libshar_raw.a -o shar_combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive libshar_raw.a -o shar_combined.o

        nm -u shar_combined.o | sed 's/.* //' | sort -u > undef_syms.txt

        objcopy --prefix-symbols=shar_ shar_combined.o

        sed 's/.*/shar_& &/' undef_syms.txt > redefine.map

        echo 'shar_uuencode_main_orig uuencode_main' >> redefine.map
        echo 'shar_uudecode_main_orig uudecode_main' >> redefine.map

        objcopy --redefine-syms=redefine.map shar_combined.o

        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libsharutils.a' shar_combined.o
    "
    WORKING_DIRECTORY "${SHAR_BUILD_REL}"
    LOGNAME "symbol-isolate-${TARGET_TRIPLET}"
)

set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
