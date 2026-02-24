vcpkg_download_distfile(ARCHIVE
    URLS "https://busybox.net/downloads/busybox-1.37.0.tar.bz2"
    FILENAME "busybox-1.37.0.tar.bz2"
    SHA512 ad8fd06f082699774f990a53d7a73b189ed404fe0a2166aff13eae4d9d8ee5c9239493befe949c98801fe7897520dbff3ed0224faa7205854ce4fa975e18467e
)

vcpkg_extract_source_archive(SOURCE_PATH ARCHIVE "${ARCHIVE}")

# Get the bb_namespace.h path
set(BB_NAMESPACE_H "${CURRENT_PORT_DIR}/../../src/bb_namespace.h")

# Detect toolchain flags (CFLAGS, LDFLAGS, CC) from vcpkg/cmake so that
# alpine-clang-vcpkg EXTRA_* flags (LTO, -Oz, -ffunction-sections, etc.)
# propagate into the raw-make build without hardcoding them here.
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

set(BB_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(BB_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")
string(APPEND BB_CFLAGS " -DNDEBUG -include ${BB_NAMESPACE_H}")
set(BB_LDFLAGS "${VCPKG_DETECTED_CMAKE_EXE_LINKER_FLAGS} ${VCPKG_DETECTED_CMAKE_EXE_LINKER_FLAGS_RELEASE}")
string(APPEND BB_LDFLAGS " -static")

# busybox uses kbuild (make), not CMake/autotools
# We need to build with -include bb_namespace.h and -DBUSYQ_NO_BUSYBOX_MAIN
set(BB_BUILD_DIR "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")
file(MAKE_DIRECTORY "${BB_BUILD_DIR}")

# Copy config to build dir only (source tree must stay clean for out-of-tree builds)
file(COPY "${CURRENT_PORT_DIR}/../../config/busybox.config"
     DESTINATION "${BB_BUILD_DIR}")
file(RENAME "${BB_BUILD_DIR}/busybox.config" "${BB_BUILD_DIR}/.config")

# Build busybox including its native binary (busybox_unstripped).
# We do NOT pass -Dmain=busybox_main here so the binary links normally with
# its own main().  We collect the .o files afterward to create libbusybox.a
# for our final link, where we recompile appletlib.o with -Dmain=busybox_main.
vcpkg_execute_required_process(
    COMMAND make
        -C "${SOURCE_PATH}"
        "O=${BB_BUILD_DIR}"
        "CC=${BB_CC}"
        "HOSTCC=${BB_CC}"
        "CFLAGS=${BB_CFLAGS}"
        "LDFLAGS=${BB_LDFLAGS}"
        -j8
        busybox_unstripped
    WORKING_DIRECTORY "${BB_BUILD_DIR}"
    LOGNAME "build-busybox-${TARGET_TRIPLET}"
)

# Recompile appletlib.o with -Dmain=bb_entry_main so busybox's main() is
# available as bb_entry_main() — just like bash_main, curl_main, jq_main.
# We use bb_entry_main (not busybox_main) because busybox already has a
# busybox_main() function for the "busybox" applet itself.
vcpkg_execute_required_process(
    COMMAND sh -c "make -C '${SOURCE_PATH}' 'O=${BB_BUILD_DIR}' 'CC=${BB_CC}' 'HOSTCC=${BB_CC}' 'CFLAGS=${BB_CFLAGS} -Dmain=bb_entry_main' libbb/appletlib.o"
    WORKING_DIRECTORY "${BB_BUILD_DIR}"
    LOGNAME "recompile-appletlib-${TARGET_TRIPLET}"
)

# Collect all .o files into libbusybox.a
# Exclude built-in.o (kbuild thin archives, not real object files) and scripts/
file(GLOB_RECURSE BB_OBJS "${BB_BUILD_DIR}/*.o")
list(FILTER BB_OBJS EXCLUDE REGEX "scripts/")
list(FILTER BB_OBJS EXCLUDE REGEX "built-in\\.o$")
list(LENGTH BB_OBJS BB_OBJ_COUNT)
if(BB_OBJ_COUNT LESS 10)
    message(FATAL_ERROR "busybox build produced only ${BB_OBJ_COUNT} .o files — build likely failed")
endif()

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

vcpkg_execute_required_process(
    COMMAND ar rcs "${CURRENT_PACKAGES_DIR}/lib/libbusybox.a" ${BB_OBJS}
    WORKING_DIRECTORY "${BB_BUILD_DIR}"
    LOGNAME "ar-libbusybox-${TARGET_TRIPLET}"
)

# Install key busybox headers
file(INSTALL
    "${BB_BUILD_DIR}/include/autoconf.h"
    DESTINATION "${CURRENT_PACKAGES_DIR}/include/busybox"
    OPTIONAL
)

# Install copyright
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
