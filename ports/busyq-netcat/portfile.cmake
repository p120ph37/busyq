# busyq-netcat: OpenBSD netcat (nc) from Debian source
#
# Downloads the Debian-packaged OpenBSD netcat source, applies all Debian
# portability patches (Linux porting, TLS removal, feature additions) and
# Alpine's b64.patch.  musl compat is handled via bsd/ wrapper headers
# plus standalone compat files for functions musl lacks (strtonum,
# arc4random, readpassphrase).  musl provides strlcpy/strlcat/
# explicit_bzero natively.
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
            case \"\$patch\" in \\#*|'') continue ;; esac
            patch -p1 < debian/patches/\"\$patch\"
        done < debian/patches/series
    "
    WORKING_DIRECTORY "${SOURCE_PATH}"
    LOGNAME "apply-debian-patches-${TARGET_TRIPLET}"
)

# musl compat: create bsd/ wrapper headers so #include <bsd/*.h> resolves
# without libbsd.  musl provides strlcpy/strlcat/explicit_bzero natively.
# strtonum, arc4random, and readpassphrase are shipped as standalone compat files.
# Wrapper headers are more robust than patching because Debian patches may
# add new #include <bsd/*.h> lines that a static patch wouldn't cover.
file(MAKE_DIRECTORY "${SOURCE_PATH}/bsd")
file(WRITE "${SOURCE_PATH}/bsd/stdlib.h" "\
/* musl compat wrapper — musl lacks strtonum/arc4random (libbsd functions) */\n\
#include <stdlib.h>\n\
#include <stdint.h>\n\
long long strtonum(const char *, long long, long long, const char **);\n\
uint32_t arc4random(void);\n\
uint32_t arc4random_uniform(uint32_t);\n\
void arc4random_buf(void *, size_t);\n")
file(WRITE "${SOURCE_PATH}/bsd/string.h" "/* musl provides strlcpy/strlcat/explicit_bzero natively */\n#include <string.h>\n")
file(WRITE "${SOURCE_PATH}/bsd/readpassphrase.h" "#include \"../readpassphrase.h\"\n")

# Copy compat files into source tree
file(COPY
    "${CURRENT_PORT_DIR}/base64.c"
    "${CURRENT_PORT_DIR}/readpassphrase.c"
    "${CURRENT_PORT_DIR}/readpassphrase.h"
    "${CURRENT_PORT_DIR}/strtonum.c"
    "${CURRENT_PORT_DIR}/arc4random.c"
    DESTINATION "${SOURCE_PATH}"
)

# Detect toolchain flags
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

# Only build release (debug artifacts are unused)
set(VCPKG_BUILD_TYPE release)

set(NC_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(NC_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

set(NC_BUILD_DIR "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")
file(MAKE_DIRECTORY "${NC_BUILD_DIR}")

# Compile all source files with -Dmain=nc_main to rename the entry point.
# Source files: netcat.c atomicio.c socks.c + compat files
# -D_GNU_SOURCE -D_BSD_SOURCE: enable musl BSD compat symbols
# -DDEBIAN_VERSION: version string shown in help output
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e
        for src in netcat.c atomicio.c socks.c base64.c readpassphrase.c strtonum.c arc4random.c; do
            '${NC_CC}' ${NC_CFLAGS} \
                -D_GNU_SOURCE -D_BSD_SOURCE \
                -DDEBIAN_VERSION='\"1.226-1.1\"' \
                -Dmain=nc_main \
                -I'${SOURCE_PATH}' \
                -c '${SOURCE_PATH}'/\"\$src\" \
                -o \"\${src%.c}.o\"
        done
    "
    WORKING_DIRECTORY "${NC_BUILD_DIR}"
    LOGNAME "build-nc-${TARGET_TRIPLET}"
)

# Package with symbol localization (busyq_package_objects keeps only *_main
# global, preventing collisions like 'timeout' vs coreutils)
file(GLOB NC_OBJS "${NC_BUILD_DIR}/*.o")
busyq_package_objects(libnc.a "${NC_BUILD_DIR}" OBJECTS ${NC_OBJS})

busyq_finalize_port(COPYRIGHT "${SOURCE_PATH}/debian/copyright")
