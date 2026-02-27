vcpkg_download_distfile(ARCHIVE
    URLS "https://github.com/lsof-org/lsof/releases/download/4.99.3/lsof-4.99.3.tar.gz"
    FILENAME "lsof-4.99.3.tar.gz"
    SHA512 83f62f62fa273becfdded4e553d398bafebf0186c7f8ac86a800dabf63ef0614c3c546b6dcd6d13f30c97ab33088a82e1e6b66cc8ed61f700c54487cab19d009
)

vcpkg_extract_source_archive(SOURCE_PATH ARCHIVE "${ARCHIVE}")

# Detect toolchain flags (CC, CFLAGS with LTO/optimization) before autotools
# claims the build directory.
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

set(LSOF_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(LSOF_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

# Build lsof with autotools (modern lsof >= 4.99.0 uses autotools).
# FORCE_UNSAFE_CONFIGURE=1: allow running configure as root inside containers
set(ENV{FORCE_UNSAFE_CONFIGURE} "1")

vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --disable-shared
        --enable-static
)

vcpkg_build_make()

set(LSOF_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# --- Symbol isolation ---
# lsof is a single-binary tool with one main(). Strategy:
#
# 1. Collect all .o files from the build
# 2. Combine into one relocatable object with ld -r
# 3. Record undefined symbols (external deps: libc, etc.)
# 4. Prefix ALL symbols with lsof_
# 5. Unprefix external deps so libc calls work
# 6. Rename lsof_main → lsof_main (our entry point)
# 7. Package into liblsof.a

# Step 1: Collect all object files from the build
file(GLOB_RECURSE LSOF_OBJS
    "${LSOF_BUILD_REL}/src/*.o"
    "${LSOF_BUILD_REL}/lib/*.o"
)
list(FILTER LSOF_OBJS EXCLUDE REGEX "/(tests|testsuite|man|doc)/")

if(NOT LSOF_OBJS)
    message(FATAL_ERROR "No lsof object files found in ${LSOF_BUILD_REL}")
endif()

# Step 1a: Pack into temporary archive (needed for ld -r --whole-archive)
vcpkg_execute_required_process(
    COMMAND ar rcs "${LSOF_BUILD_REL}/liblsof_raw.a" ${LSOF_OBJS}
    WORKING_DIRECTORY "${LSOF_BUILD_REL}"
    LOGNAME "ar-raw-${TARGET_TRIPLET}"
)

# Steps 2-7: Combine, prefix, unprefix, rename — all in one script
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e

        # Step 2: Combine all objects into one relocatable .o
        ld -r --whole-archive liblsof_raw.a -o lsof_combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive liblsof_raw.a -o lsof_combined.o

        # Step 3: Record undefined symbols (external deps: libc, etc.)
        nm -u lsof_combined.o | sed 's/.* //' | sort -u > undef_syms.txt

        # Step 4: Prefix all symbols with lsof_
        objcopy --prefix-symbols=lsof_ lsof_combined.o

        # Step 5: Generate redefine map to unprefix external deps
        # After prefixing, 'malloc' became 'lsof_malloc' (undefined).
        # Map it back: lsof_malloc -> malloc
        sed 's/.*/lsof_& &/' undef_syms.txt > redefine.map

        # Step 6: Rename lsof_main -> lsof_main (entry point)
        # After prefix-symbols, the original 'main' became 'lsof_main'.
        # That is already the name we want, so no additional rename needed.
        # But we must ensure it is NOT un-prefixed if 'main' appears in
        # undef_syms.txt (it should not, since main is defined, not undefined).

        objcopy --redefine-syms=redefine.map lsof_combined.o

        # Step 7: Package into final archive
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/liblsof.a' lsof_combined.o
    "
    WORKING_DIRECTORY "${LSOF_BUILD_REL}"
    LOGNAME "symbol-isolate-${TARGET_TRIPLET}"
)

# Suppress vcpkg post-build warnings — we only produce release libraries
# and lsof has no public headers needed by busyq (it's a tool, not a library API)
set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

# Install copyright
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
