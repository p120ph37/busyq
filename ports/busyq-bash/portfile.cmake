# Only build release (debug artifacts are unused)
set(VCPKG_BUILD_TYPE release)

vcpkg_download_distfile(ARCHIVE
    URLS
        "https://ftpmirror.gnu.org/gnu/bash/bash-5.3.tar.gz"
        "https://mirrors.kernel.org/gnu/bash/bash-5.3.tar.gz"
        "https://ftp.gnu.org/gnu/bash/bash-5.3.tar.gz"
    FILENAME "bash-5.3.tar.gz"
    SHA512 426702c8b0fb9e0c9956259973ce5b657890fd47f4f807a64febf20077bb48d0b91474ed6e843d2ef277186b46c5fffa79b808da9b48d4ec027d5e2de1b28ed8
)

vcpkg_extract_source_archive(SOURCE_PATH
    ARCHIVE "${ARCHIVE}"
    PATCHES
        applet-command-lookup.patch
        applet-execute.patch
)

# Apply official GNU bash incremental patches (5.3.1 through 5.3.3).
# These use -p0 format from the parent directory (../bash-5.3/file),
# matching Alpine's application method.
foreach(_patch_num 001 002 003)
    vcpkg_execute_required_process(
        COMMAND patch -p0 -i "${CMAKE_CURRENT_LIST_DIR}/patches/bash53-${_patch_num}.patch"
        WORKING_DIRECTORY "${SOURCE_PATH}"
        LOGNAME "bash-patch-${_patch_num}"
    )
endforeach()

# Copy applet table header into bash source tree so compilation can find it
file(COPY
    "${CURRENT_PORT_DIR}/../../src/applet_table.h"
    DESTINATION "${SOURCE_PATH}"
    FILE_PERMISSIONS OWNER_READ OWNER_WRITE
)
file(RENAME "${SOURCE_PATH}/applet_table.h" "${SOURCE_PATH}/busyq_applet_table.h")

# Provide a stub for busyq_find_applet so bash can link during its build.
# The real implementation comes from applets.c at final link time.
file(WRITE "${SOURCE_PATH}/busyq_stub.c" [=[
#include "busyq_applet_table.h"
const struct busyq_applet *busyq_find_applet(const char *name) { (void)name; return 0; }
]=])

# Bash uses autotools.
# We do NOT pass -Dmain=bash_main in CFLAGS because it breaks configure tests.
# Instead we recompile shell.c separately after the build.
vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --enable-static-link
        --without-bash-malloc
        --disable-nls
)

# Compile the stub object in each build directory so the link step can find the symbol.
# We do this after configure (which creates the build dirs) but before make.
foreach(BUILDTYPE IN ITEMS "rel" "dbg")
    set(_build_dir "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-${BUILDTYPE}")
    if(EXISTS "${_build_dir}/Makefile")
        vcpkg_execute_required_process(
            COMMAND sh -c "cc -DHAVE_CONFIG_H -DSHELL -I'${_build_dir}' -I'${SOURCE_PATH}' -I'${SOURCE_PATH}/include' -c '${SOURCE_PATH}/busyq_stub.c' -o '${_build_dir}/busyq_stub.o'"
            WORKING_DIRECTORY "${_build_dir}"
            LOGNAME "compile-busyq-stub-${TARGET_TRIPLET}-${BUILDTYPE}"
        )
    endif()
endforeach()

# Build with LOCAL_LIBS pointing to the stub object so bash can link
vcpkg_build_make(
    LOGFILE_ROOT "build"
    OPTIONS "LOCAL_LIBS=busyq_stub.o"
)

set(BASH_BUILD_DIR "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# Bash doesn't produce a single libbash.a. Collect top-level .o files
# and pack them, plus install sub-libraries.
file(GLOB BASH_OBJS "${BASH_BUILD_DIR}/*.o")
# Exclude build-time utility objects that shouldn't be in the library
list(FILTER BASH_OBJS EXCLUDE REGEX "busyq_stub\\.o$")
list(FILTER BASH_OBJS EXCLUDE REGEX "mksignames\\.o$")
list(FILTER BASH_OBJS EXCLUDE REGEX "mksyntax\\.o$")

if(BASH_OBJS)
    vcpkg_execute_required_process(
        COMMAND ar rcs "${CURRENT_PACKAGES_DIR}/lib/libbash.a" ${BASH_OBJS}
        WORKING_DIRECTORY "${BASH_BUILD_DIR}"
        LOGNAME "ar-libbash-${TARGET_TRIPLET}"
    )
endif()

# Recompile shell.o with -Dmain=bash_main using make (to pick up all SYSTEM_FLAGS)
# and replace it in the archive
vcpkg_execute_required_process(
    COMMAND sh -c "rm -f shell.o && make shell.o 'ADDON_CFLAGS=-Dmain=bash_main' && ar d '${CURRENT_PACKAGES_DIR}/lib/libbash.a' shell.o && ar rs '${CURRENT_PACKAGES_DIR}/lib/libbash.a' shell.o"
    WORKING_DIRECTORY "${BASH_BUILD_DIR}"
    LOGNAME "compile-bash-main-rename-${TARGET_TRIPLET}"
)

# Install sub-libraries
foreach(SUBLIB IN ITEMS
    "builtins/libbuiltins.a"
    "lib/readline/libreadline.a"
    "lib/readline/libhistory.a"
    "lib/glob/libglob.a"
    "lib/tilde/libtilde.a"
    "lib/sh/libsh.a"
)
    if(EXISTS "${BASH_BUILD_DIR}/${SUBLIB}")
        file(INSTALL "${BASH_BUILD_DIR}/${SUBLIB}" DESTINATION "${CURRENT_PACKAGES_DIR}/lib")
    endif()
endforeach()

# Remove readline/history shell.o stubs — bash provides the real implementations of
# sh_single_quote, sh_set_lines_and_columns, sh_get_env_value, etc.
# Both libreadline.a and libhistory.a contain fallback shell.o.
foreach(RLIB IN ITEMS "libreadline.a" "libhistory.a")
    if(EXISTS "${CURRENT_PACKAGES_DIR}/lib/${RLIB}")
        vcpkg_execute_required_process(
            COMMAND ar d "${CURRENT_PACKAGES_DIR}/lib/${RLIB}" shell.o
            WORKING_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib"
            LOGNAME "strip-${RLIB}-shell-${TARGET_TRIPLET}"
        )
    endif()
endforeach()

# --- Build the busyq-scan AST walker ---
# This must be compiled here (not in the top-level CMakeLists.txt) because
# it needs bash's internal headers (command.h, shell.h, flags.h, etc.)
# which are only available inside the bash source/build tree.
set(_scan_walk_src "${CURRENT_PORT_DIR}/../../src/busyq_scan_walk.c")
if(EXISTS "${_scan_walk_src}")
    vcpkg_execute_required_process(
        COMMAND sh -c "cc -DHAVE_CONFIG_H -DSHELL -I'${BASH_BUILD_DIR}' -I'${SOURCE_PATH}' -I'${SOURCE_PATH}/include' -I'${SOURCE_PATH}/builtins' ${EXTRA_CFLAGS} -c '${_scan_walk_src}' -o '${BASH_BUILD_DIR}/busyq_scan_walk.o'"
        WORKING_DIRECTORY "${BASH_BUILD_DIR}"
        LOGNAME "compile-busyq-scan-walk-${TARGET_TRIPLET}"
    )
    vcpkg_execute_required_process(
        COMMAND ar rcs "${CURRENT_PACKAGES_DIR}/lib/libbusyq_scan.a" "${BASH_BUILD_DIR}/busyq_scan_walk.o"
        WORKING_DIRECTORY "${BASH_BUILD_DIR}"
        LOGNAME "ar-libbusyq-scan-${TARGET_TRIPLET}"
    )
endif()

# Install key headers
file(INSTALL
    "${SOURCE_PATH}/shell.h"
    "${SOURCE_PATH}/busyq_applet_table.h"
    DESTINATION "${CURRENT_PACKAGES_DIR}/include/bash"
)

# Suppress vcpkg post-build warnings — we only produce release libraries
set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)

# Install copyright
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
