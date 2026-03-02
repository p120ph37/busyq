# busyq-netcat: OpenBSD netcat (nc) from Debian source
#
# Downloads the Debian-packaged OpenBSD netcat source, applies all Debian
# portability patches (Linux porting, TLS removal, feature additions),
# Alpine's b64.patch, and a busyq-specific musl-compat patch that removes
# the libbsd dependency (musl provides strtonum/strlcpy/strlcat/explicit_bzero
# natively; readpassphrase is shipped as a standalone compat file).
#
# No symbol isolation needed -- no gnulib, no symbol collisions.

include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_alpine_helpers.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_symbol_helpers.cmake")

# Download and extract source, applying Alpine's b64.patch
busyq_alpine_source(
    PORT_DIR "${CMAKE_CURRENT_LIST_DIR}"
    OUT_SOURCE_PATH SOURCE_PATH
    USE_PATCH_CMD
)

# Apply Debian patches from inside the tarball (debian/patches/series)
vcpkg_execute_required_process(
    COMMAND sh -c "
        while read -r patch; do
            case \"\\$patch\" in \\#*|'') continue ;; esac
            patch -p1 < debian/patches/\"\\$patch\"
        done < debian/patches/series
    "
    WORKING_DIRECTORY "${SOURCE_PATH}"
    LOGNAME "apply-debian-patches-${TARGET_TRIPLET}"
)

# Apply busyq musl-compat patch (removes libbsd dependency)
vcpkg_execute_required_process(
    COMMAND patch -p1 -i "${CURRENT_PORT_DIR}/patches/musl-compat.patch"
    WORKING_DIRECTORY "${SOURCE_PATH}"
    LOGNAME "apply-musl-compat-${TARGET_TRIPLET}"
)

# Copy compat files into source tree
file(COPY
    "${CURRENT_PORT_DIR}/base64.c"
    "${CURRENT_PORT_DIR}/readpassphrase.c"
    "${CURRENT_PORT_DIR}/readpassphrase.h"
    DESTINATION "${SOURCE_PATH}"
)

# Detect toolchain flags
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

# Only build release (debug artifacts are unused)
set(VCPKG_BUILD_TYPE release)

set(NC_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(NC_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

set(NC_BUILD_DIR "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")
file(MAKE_DIRECTORY "${NC_BUILD_DIR}")

# Compile all source files with -Dmain=nc_main to rename the entry point.
# Source files: netcat.c atomicio.c socks.c base64.c readpassphrase.c
# -D_GNU_SOURCE -D_BSD_SOURCE: enable musl BSD compat symbols
# -DDEBIAN_VERSION: version string shown in help output
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e
        for src in netcat.c atomicio.c socks.c base64.c readpassphrase.c; do
            '${NC_CC}' ${NC_CFLAGS} \
                -D_GNU_SOURCE -D_BSD_SOURCE \
                -DDEBIAN_VERSION='\"1.226-1.1\"' \
                -Dmain=nc_main \
                -I'${SOURCE_PATH}' \
                -c '${SOURCE_PATH}'/\"\$src\" \
                -o \"\${src%.c}.o\"
        done
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libnc.a' \
            netcat.o atomicio.o socks.o base64.o readpassphrase.o
    "
    WORKING_DIRECTORY "${NC_BUILD_DIR}"
    LOGNAME "build-nc-${TARGET_TRIPLET}"
)

busyq_finalize_port(COPYRIGHT "${SOURCE_PATH}/COPYING")
