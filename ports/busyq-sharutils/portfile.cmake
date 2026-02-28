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
include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_symbol_helpers.cmake")

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

# Rename main() at source level for each tool (LTO-safe — objcopy can't
# rename symbols in LLVM bitcode objects)
foreach(_tool shar unshar uuencode uudecode)
    set(_file "${SOURCE_PATH}/src/${_tool}.c")
    if(EXISTS "${_file}")
        file(READ "${_file}" _content)
        file(WRITE "${_file}" "#define main ${_tool}_main\n${_content}")
    endif()
endforeach()

# Detect toolchain flags
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

# Only build release (debug artifacts are unused)
set(VCPKG_BUILD_TYPE release)

# --- Generate compile-time symbol prefix header (LTO-safe) ---
set(_prefix_h "${SOURCE_PATH}/shar_prefix.h")
busyq_gen_prefix_header(shar "${_prefix_h}")

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

vcpkg_build_make(OPTIONS "CPPFLAGS=-include ${_prefix_h}")

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

# Combine objects and package (mains already renamed at source level)
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e

        # Combine all objects into one relocatable .o
        ld -r --whole-archive libshar_raw.a -o combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive libshar_raw.a -o combined.o

        # Package into final archive
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libsharutils.a' combined.o
    "
    WORKING_DIRECTORY "${SHAR_BUILD_REL}"
    LOGNAME "combine-${TARGET_TRIPLET}"
)

set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
