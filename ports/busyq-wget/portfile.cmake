vcpkg_download_distfile(ARCHIVE
    URLS "https://ftpmirror.gnu.org/gnu/wget/wget-1.25.tar.gz"
         "https://mirrors.kernel.org/gnu/wget/wget-1.25.tar.gz"
         "https://ftp.gnu.org/gnu/wget/wget-1.25.tar.gz"
    FILENAME "wget-1.25.tar.gz"
    SHA512 0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
)

vcpkg_extract_source_archive(SOURCE_PATH ARCHIVE "${ARCHIVE}")

# Detect toolchain flags (CC, CFLAGS with LTO/optimization) before autotools
# claims the build directory.
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

set(WGET_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(WGET_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

# Build wget without SSL (users have curl for HTTPS).
# wget embeds gnulib, so full symbol isolation is critical.
# --disable-nls: no internationalization (smaller binary)
# --without-ssl: no SSL support (curl handles HTTPS)
# --disable-ntlm: no NTLM authentication
# --disable-debug: no debug output
# --without-metalink: no metalink support
# --disable-pcre / --disable-pcre2: no regex matching
# --without-libuuid: no UUID support
# --without-libidn: no IDN support
# --without-zlib: no compression (curl already handles this)
# FORCE_UNSAFE_CONFIGURE=1: allow running configure as root inside containers
set(ENV{FORCE_UNSAFE_CONFIGURE} "1")

vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --disable-nls
        --without-ssl
        --disable-ntlm
        --disable-debug
        --without-metalink
        --disable-pcre
        --disable-pcre2
        --without-libuuid
        --without-libidn
        --without-zlib
)

vcpkg_build_make()

set(WGET_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# --- Symbol isolation ---
# wget embeds gnulib, causing symbol collisions with bash, coreutils, etc.
# Strategy:
#
# 1. Collect all .o files into a temporary archive
# 2. Use ld -r to combine into one relocatable object (resolves internal dupes)
# 3. Record all undefined symbols (= external deps: libc, pthreads, etc.)
# 4. Prefix ALL symbols with wget_ (namespaces everything)
# 5. Unprefix the external deps so they link against libc correctly
# 6. Rename wget_main -> wget_main (dispatch entry point)
# 7. Package into libwget.a

# Step 1: Collect all object files from the build
file(GLOB_RECURSE WGET_OBJS
    "${WGET_BUILD_REL}/src/*.o"
    "${WGET_BUILD_REL}/lib/*.o"
)
list(FILTER WGET_OBJS EXCLUDE REGEX "/(tests|testenv|fuzz)/")

if(NOT WGET_OBJS)
    message(FATAL_ERROR "No wget object files found in ${WGET_BUILD_REL}")
endif()

# Step 1a: Pack into temporary archive (needed for ld -r --whole-archive)
vcpkg_execute_required_process(
    COMMAND ar rcs "${WGET_BUILD_REL}/libwget_raw.a" ${WGET_OBJS}
    WORKING_DIRECTORY "${WGET_BUILD_REL}"
    LOGNAME "ar-raw-${TARGET_TRIPLET}"
)

# Steps 2-7: Combine, prefix, unprefix, rename -- all in one script
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e

        # Step 2: Combine all objects into one relocatable .o
        ld -r --whole-archive libwget_raw.a -o wget_combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive libwget_raw.a -o wget_combined.o

        # Step 3: Record undefined symbols (external deps: libc, pthreads, etc.)
        nm -u wget_combined.o | sed 's/.* //' | sort -u > undef_syms.txt

        # Step 4: Prefix all symbols with wget_
        objcopy --prefix-symbols=wget_ wget_combined.o

        # Step 5: Generate redefine map to unprefix external deps
        sed 's/.*/wget_& &/' undef_syms.txt > redefine.map

        # Step 6: Rename wget_main -> wget_main (entry point)
        echo 'wget_main wget_main' >> redefine.map

        objcopy --redefine-syms=redefine.map wget_combined.o

        # Step 7: Package into final archive
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libwget.a' wget_combined.o
    "
    WORKING_DIRECTORY "${WGET_BUILD_REL}"
    LOGNAME "symbol-isolate-${TARGET_TRIPLET}"
)

# Suppress vcpkg post-build warnings -- we only produce release libraries
# and wget has no public headers (it's a tool, not a library)
set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

# Install copyright
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
