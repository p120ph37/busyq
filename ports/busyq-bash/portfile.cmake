vcpkg_download_distfile(ARCHIVE
    URLS "https://ftp.gnu.org/gnu/bash/bash-5.3.tar.gz"
    FILENAME "bash-5.3.tar.gz"
    SHA512 0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
)

vcpkg_extract_source_archive(SOURCE_PATH ARCHIVE "${ARCHIVE}")

# Copy applet table header into bash source tree so patches can find it
file(COPY
    "${CURRENT_PORT_DIR}/../../src/applet_table.h"
    DESTINATION "${SOURCE_PATH}"
    FILE_PERMISSIONS OWNER_READ OWNER_WRITE
)
file(RENAME "${SOURCE_PATH}/applet_table.h" "${SOURCE_PATH}/busyq_applet_table.h")

# Apply busyq patches
vcpkg_apply_patches(
    SOURCE_PATH "${SOURCE_PATH}"
    PATCHES
        applet-command-lookup.patch
        applet-execute.patch
)

# Bash uses autotools.
# We rename main() via CFLAGS and build as a set of static libraries.
vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --enable-static-link
        --without-bash-malloc
        --disable-nls
    OPTIONS_RELEASE
        "CFLAGS=-Dmain=bash_main -ffunction-sections -fdata-sections -Oz -DNDEBUG"
        "LDFLAGS=-Wl,--gc-sections -static"
    OPTIONS_DEBUG
        "CFLAGS=-Dmain=bash_main -g"
)

vcpkg_build_make()

# Bash builds several static libraries we need:
# - libbash (the main bash objects, may not exist as a separate lib)
# - builtins/libbuiltins.a
# - lib/readline/libreadline.a and lib/readline/libhistory.a
# - lib/glob/libglob.a
# - lib/tilde/libtilde.a
# - lib/sh/libsh.a
#
# We need to collect all the .o files from the bash build and archive them.

set(BASH_BUILD_DIR "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

# Collect all bash object files into a single archive for ease of linking
file(GLOB BASH_OBJS "${BASH_BUILD_DIR}/*.o")
# Remove the main.o since we compile our own main
list(FILTER BASH_OBJS EXCLUDE REGEX "shell\\.o$")

# Install the sub-libraries directly
file(GLOB BASH_BUILTINS_LIB "${BASH_BUILD_DIR}/builtins/libbuiltins.a")
file(GLOB BASH_READLINE_LIB "${BASH_BUILD_DIR}/lib/readline/libreadline.a")
file(GLOB BASH_HISTORY_LIB "${BASH_BUILD_DIR}/lib/readline/libhistory.a")
file(GLOB BASH_GLOB_LIB "${BASH_BUILD_DIR}/lib/glob/libglob.a")
file(GLOB BASH_TILDE_LIB "${BASH_BUILD_DIR}/lib/tilde/libtilde.a")
file(GLOB BASH_SH_LIB "${BASH_BUILD_DIR}/lib/sh/libsh.a")

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# Create libbash.a from the main bash objects
if(BASH_OBJS)
    vcpkg_execute_required_process(
        COMMAND ar rcs "${CURRENT_PACKAGES_DIR}/lib/libbash.a" ${BASH_OBJS}
        WORKING_DIRECTORY "${BASH_BUILD_DIR}"
        LOGNAME "ar-libbash-${TARGET_TRIPLET}"
    )
endif()

# Install sub-libraries
foreach(LIB IN ITEMS
    ${BASH_BUILTINS_LIB}
    ${BASH_READLINE_LIB}
    ${BASH_HISTORY_LIB}
    ${BASH_GLOB_LIB}
    ${BASH_TILDE_LIB}
    ${BASH_SH_LIB}
)
    if(LIB)
        file(INSTALL ${LIB} DESTINATION "${CURRENT_PACKAGES_DIR}/lib")
    endif()
endforeach()

# Install key headers
file(INSTALL
    "${SOURCE_PATH}/shell.h"
    "${SOURCE_PATH}/busyq_applet_table.h"
    DESTINATION "${CURRENT_PACKAGES_DIR}/include/bash"
)

# Install copyright
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
