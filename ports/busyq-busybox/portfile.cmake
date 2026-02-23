vcpkg_download_distfile(ARCHIVE
    URLS "https://busybox.net/downloads/busybox-1.37.0.tar.bz2"
    FILENAME "busybox-1.37.0.tar.bz2"
    SHA512 0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
)

vcpkg_extract_source_archive(SOURCE_PATH ARCHIVE "${ARCHIVE}")

# Apply busyq patches
vcpkg_apply_patches(
    SOURCE_PATH "${SOURCE_PATH}"
    PATCHES
        remove-main.patch
)

# Copy our busybox config
file(COPY "${CURRENT_PORT_DIR}/../../config/busybox.config"
     DESTINATION "${SOURCE_PATH}")
file(RENAME "${SOURCE_PATH}/busybox.config" "${SOURCE_PATH}/.config")

# Get the bb_namespace.h path
set(BB_NAMESPACE_H "${CURRENT_PORT_DIR}/../../src/bb_namespace.h")

# busybox uses kbuild (make), not CMake/autotools
# We need to build with -include bb_namespace.h and -DBUSYQ_NO_BUSYBOX_MAIN
set(BB_BUILD_DIR "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")
file(MAKE_DIRECTORY "${BB_BUILD_DIR}")

# Copy config to build dir
file(COPY "${SOURCE_PATH}/.config" DESTINATION "${BB_BUILD_DIR}")

# Build busybox with our custom flags
vcpkg_execute_required_process(
    COMMAND make
        -C "${SOURCE_PATH}"
        "O=${BB_BUILD_DIR}"
        "CC=${CMAKE_C_COMPILER}"
        "CFLAGS=-ffunction-sections -fdata-sections -Oz -DNDEBUG -include ${BB_NAMESPACE_H} -DBUSYQ_NO_BUSYBOX_MAIN"
        "LDFLAGS=-Wl,--gc-sections -static"
        "CONFIG_PREFIX=${CURRENT_PACKAGES_DIR}"
        -j${VCPKG_CONCURRENCY}
        busybox_unstripped
    WORKING_DIRECTORY "${BB_BUILD_DIR}"
    LOGNAME "build-busybox-${TARGET_TRIPLET}"
)

# busybox builds produce .o files; we need to create libbusybox.a
# Collect all relevant .o files from the build
file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# The busybox build creates a busybox_unstripped binary.
# With CONFIG_BUILD_LIBBUSYBOX=y, it also creates libbusybox.so
# For static linking, we need to archive the .o files ourselves.
file(GLOB_RECURSE BB_OBJS "${BB_BUILD_DIR}/**/*.o")
# Filter out test objects or other non-library objects
list(FILTER BB_OBJS EXCLUDE REGEX "scripts/")
list(FILTER BB_OBJS EXCLUDE REGEX "applets/applets\\.o$")

if(BB_OBJS)
    vcpkg_execute_required_process(
        COMMAND ar rcs "${CURRENT_PACKAGES_DIR}/lib/libbusybox.a" ${BB_OBJS}
        WORKING_DIRECTORY "${BB_BUILD_DIR}"
        LOGNAME "ar-libbusybox-${TARGET_TRIPLET}"
    )
endif()

# Generate the busybox applet table header for busyq
# This parses busybox's include/applets.h to extract enabled applet metadata
set(APPLET_HEADER "${CURRENT_PACKAGES_DIR}/include/busybox_applets.h")
file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/include")

# The generated include/applet_tables.h has the data we need, but in a
# busybox-internal format. We generate our own BUSYQ_BB_APPLET() entries.
# Parse the applet names from the generated applet_tables.h
set(GEN_SCRIPT "${CURRENT_PORT_DIR}/gen_busyq_applets.sh")
if(EXISTS "${GEN_SCRIPT}")
    vcpkg_execute_required_process(
        COMMAND sh "${GEN_SCRIPT}" "${BB_BUILD_DIR}" "${APPLET_HEADER}"
        WORKING_DIRECTORY "${BB_BUILD_DIR}"
        LOGNAME "gen-applets-${TARGET_TRIPLET}"
    )
else()
    # Fallback: generate from the preprocessed applets.h
    file(WRITE "${APPLET_HEADER}" "/* Auto-generated busybox applet table - fallback */\n")
endif()

# Install key busybox headers
file(INSTALL
    "${BB_BUILD_DIR}/include/autoconf.h"
    DESTINATION "${CURRENT_PACKAGES_DIR}/include/busybox"
    OPTIONAL
)

# Install copyright
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
