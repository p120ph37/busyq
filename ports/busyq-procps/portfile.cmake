vcpkg_download_distfile(ARCHIVE
    URLS "https://sourceforge.net/projects/procps-ng/files/Production/procps-ng-4.0.4.tar.xz"
         "https://gitlab.com/procps-ng/procps/-/archive/v4.0.4/procps-v4.0.4.tar.gz"
    FILENAME "procps-ng-4.0.4.tar.xz"
    SHA512 0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
)

vcpkg_extract_source_archive(SOURCE_PATH ARCHIVE "${ARCHIVE}")

# Detect toolchain flags (CC, CFLAGS with LTO/optimization) before autotools
# claims the build directory.
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

set(PROCPS_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(PROCPS_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

# Build procps-ng with autotools.
# --disable-nls: no internationalization (smaller binary)
# --disable-shared / --enable-static: static library only
# --without-systemd: no systemd journal integration
# --disable-kill: coreutils already provides kill
# --enable-watch: build the watch utility
# FORCE_UNSAFE_CONFIGURE=1: allow running configure as root inside containers
set(ENV{FORCE_UNSAFE_CONFIGURE} "1")

vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --disable-nls
        --disable-shared
        --enable-static
        --without-systemd
        --disable-kill
        --enable-watch
)

vcpkg_build_make()

set(PROCPS_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# --- Symbol isolation ---
# procps-ng has multiple tool binaries each with their own main(), plus a
# shared libprocps library. Strategy:
#
# 1. Collect all .o files from library and tool sources
# 2. For each tool .o that defines main(), rename main → <basename>_main_orig
#    (so we can track which main belongs to which tool after prefixing)
# 3. Combine into one relocatable object with ld -r
# 4. Record undefined symbols (external deps: libc, ncurses, etc.)
# 5. Prefix ALL symbols with procps_
# 6. Unprefix external deps so libc/ncurses calls work
# 7. Rename procps_<tool>_main_orig → <tool>_main for each tool
# 8. Package into libprocps.a

# Step 1: Collect all object files from the build
file(GLOB_RECURSE PROCPS_OBJS
    "${PROCPS_BUILD_REL}/src/*.o"
    "${PROCPS_BUILD_REL}/library/*.o"
    "${PROCPS_BUILD_REL}/lib/*.o"
)
list(FILTER PROCPS_OBJS EXCLUDE REGEX "/(tests|testsuite|man|doc)/")

if(NOT PROCPS_OBJS)
    message(FATAL_ERROR "No procps-ng object files found in ${PROCPS_BUILD_REL}")
endif()

# Step 1a: Pack into temporary archive (needed for ld -r --whole-archive)
vcpkg_execute_required_process(
    COMMAND ar rcs "${PROCPS_BUILD_REL}/libprocps_raw.a" ${PROCPS_OBJS}
    WORKING_DIRECTORY "${PROCPS_BUILD_REL}"
    LOGNAME "ar-raw-${TARGET_TRIPLET}"
)

# Steps 2-8: Rename per-tool mains, combine, prefix, unprefix, rename entries
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e

        # Step 2: For each object file that defines a 'main' symbol,
        # rename main → <basename>_main_orig so we can identify them after prefixing.
        # Only process tool source .o files, not library .o files.
        for obj in src/*.o src/*/*.o; do
            [ -f \"\\$obj\" ] || continue
            if nm \"\\$obj\" 2>/dev/null | grep -q ' T main$'; then
                bn=\\$(basename \"\\$obj\" .o)
                objcopy --redefine-sym main=\\${bn}_main_orig \"\\$obj\"
            fi
        done

        # Repack the raw archive after renaming mains in-place
        find src/ library/ lib/ -name '*.o' ! -path '*/tests/*' ! -path '*/testsuite/*' 2>/dev/null | sort > obj_list.txt
        ar rcs libprocps_raw.a \\$(cat obj_list.txt) 2>/dev/null || true

        # Step 3: Combine all objects into one relocatable .o
        ld -r --whole-archive libprocps_raw.a -o procps_combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive libprocps_raw.a -o procps_combined.o

        # Step 4: Record undefined symbols (external deps: libc, ncurses, etc.)
        nm -u procps_combined.o | sed 's/.* //' | sort -u > undef_syms.txt

        # Step 5: Prefix all symbols with procps_
        objcopy --prefix-symbols=procps_ procps_combined.o

        # Step 6: Generate redefine map to unprefix external deps
        sed 's/.*/procps_& &/' undef_syms.txt > redefine.map

        # Step 7: Rename procps_<tool>_main_orig → <tool>_main for each tool
        # The tool object basenames may vary by procps-ng version; handle common names.
        # ps may be in pscommand.o or ps.o; top may be in top.o or top_main.o, etc.
        # We enumerate all _main_orig symbols actually present and map them.
        nm procps_combined.o 2>/dev/null | grep '_main_orig' | sed 's/.* //' | while read sym; do
            # sym is like procps_free_main_orig — extract the tool name
            tool=\\$(echo \"\\$sym\" | sed 's/^procps_//; s/_main_orig$//')
            echo \"\\$sym \\${tool}_main\"
        done >> redefine.map

        objcopy --redefine-syms=redefine.map procps_combined.o

        # Step 8: Package into final archive
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libprocps.a' procps_combined.o
    "
    WORKING_DIRECTORY "${PROCPS_BUILD_REL}"
    LOGNAME "symbol-isolate-${TARGET_TRIPLET}"
)

# Suppress vcpkg post-build warnings — we only produce release libraries
# and procps-ng has no public headers needed by busyq (it's tools, not a library API)
set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

# Install copyright
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
