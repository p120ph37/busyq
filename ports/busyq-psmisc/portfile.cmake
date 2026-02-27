vcpkg_download_distfile(ARCHIVE
    URLS "https://sourceforge.net/projects/psmisc/files/psmisc/psmisc-23.7.tar.xz"
         "https://gitlab.com/psmisc/psmisc/-/archive/v23.7/psmisc-v23.7.tar.gz"
    FILENAME "psmisc-23.7.tar.xz"
    SHA512 8180d24355b3b0f3102044916d078b1aa9a1af3d84f1e14db79e33e505390167012adbb1a8a5f47a692f3a14aba1eb5f1f8f37f328392e8635b89966af9b2128
)

vcpkg_extract_source_archive(SOURCE_PATH ARCHIVE "${ARCHIVE}")

# Detect toolchain flags (CC, CFLAGS with LTO/optimization) before autotools
# claims the build directory.
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

set(PSMISC_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(PSMISC_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

# Build psmisc with autotools.
# --disable-nls: no internationalization (smaller binary)
# --without-selinux: no SELinux support needed in distroless containers
# FORCE_UNSAFE_CONFIGURE=1: allow running configure as root inside containers
set(ENV{FORCE_UNSAFE_CONFIGURE} "1")

# vcpkg builds ncurses as libncursesw.a (wide-char), but psmisc's configure
# checks for -ltinfo / -lncurses / -ltermcap via AC_CHECK_LIB. Create
# compatibility symlinks so the linker check succeeds.
foreach(_libdir "${CURRENT_INSTALLED_DIR}/lib" "${CURRENT_INSTALLED_DIR}/debug/lib")
    if(EXISTS "${_libdir}/libncursesw.a" AND NOT EXISTS "${_libdir}/libncurses.a")
        file(CREATE_LINK "${_libdir}/libncursesw.a" "${_libdir}/libncurses.a" SYMBOLIC)
    endif()
    if(EXISTS "${_libdir}/libncursesw.a" AND NOT EXISTS "${_libdir}/libtinfo.a")
        file(CREATE_LINK "${_libdir}/libncursesw.a" "${_libdir}/libtinfo.a" SYMBOLIC)
    endif()
endforeach()

vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --disable-nls
        --without-selinux
)

vcpkg_build_make()

set(PSMISC_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# --- Symbol isolation ---
# psmisc has three separate tool binaries (killall, fuser, pstree), each with
# its own main(). Strategy:
#
# 1. Collect all .o files from the build
# 2. For each tool .o that defines main(), rename main → <basename>_main_orig
# 3. Combine into one relocatable object with ld -r
# 4. Record undefined symbols (external deps: libc, ncurses, etc.)
# 5. Prefix ALL symbols with psmisc_
# 6. Unprefix external deps so libc/ncurses calls work
# 7. Rename psmisc_<tool>_main_orig → <tool>_main for each tool
# 8. Package into libpsmisc.a

# Step 1: Collect all object files from the build
file(GLOB_RECURSE PSMISC_OBJS
    "${PSMISC_BUILD_REL}/src/*.o"
)
list(FILTER PSMISC_OBJS EXCLUDE REGEX "/(tests|testsuite|man|doc)/")

if(NOT PSMISC_OBJS)
    message(FATAL_ERROR "No psmisc object files found in ${PSMISC_BUILD_REL}")
endif()

# Step 1a: Pack into temporary archive (needed for ld -r --whole-archive)
vcpkg_execute_required_process(
    COMMAND ar rcs "${PSMISC_BUILD_REL}/libpsmisc_raw.a" ${PSMISC_OBJS}
    WORKING_DIRECTORY "${PSMISC_BUILD_REL}"
    LOGNAME "ar-raw-${TARGET_TRIPLET}"
)

# Steps 2-8: Rename per-tool mains, combine, prefix, unprefix, rename entries
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e

        # Step 2: For each object file that defines a 'main' symbol,
        # rename main → <basename>_main_orig so we can identify them after prefixing.
        for obj in src/*.o
do
            [ -f \"\$obj\" ] || continue
            if nm \"\$obj\" 2>/dev/null | grep -q ' T main$'
then
                bn=\$(basename \"\$obj\" .o)
                objcopy --redefine-sym main=\${bn}_main_orig \"\$obj\"
            fi
        done

        # Repack the raw archive after renaming mains in-place
        find src/ -name '*.o' ! -path '*/tests/*' ! -path '*/testsuite/*' 2>/dev/null | sort > obj_list.txt
        ar rcs libpsmisc_raw.a \$(cat obj_list.txt) 2>/dev/null || true

        # Step 3: Combine all objects into one relocatable .o
        ld -r --whole-archive libpsmisc_raw.a -o psmisc_combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive libpsmisc_raw.a -o psmisc_combined.o

        # Step 4: Record undefined symbols (external deps: libc, ncurses, etc.)
        nm -u psmisc_combined.o | sed 's/.* //' | sort -u > undef_syms.txt

        # Step 5: Prefix all symbols with psmisc_
        objcopy --prefix-symbols=psmisc_ psmisc_combined.o

        # Step 6: Generate redefine map to unprefix external deps
        sed 's/.*/psmisc_& &/' undef_syms.txt > redefine.map

        # Step 7: Rename psmisc_<tool>_main_orig → <tool>_main for each tool
        # Enumerate all _main_orig symbols actually present and map them.
        nm psmisc_combined.o 2>/dev/null | grep '_main_orig' | sed 's/.* //' | while read sym
do
            # sym is like psmisc_killall_main_orig — extract the tool name
            tool=\$(echo \"\$sym\" | sed 's/^psmisc_//; s/_main_orig$//')
            echo \"\$sym \${tool}_main\"
        done >> redefine.map

        objcopy --redefine-syms=redefine.map psmisc_combined.o

        # Step 8: Package into final archive
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libpsmisc.a' psmisc_combined.o
    "
    WORKING_DIRECTORY "${PSMISC_BUILD_REL}"
    LOGNAME "symbol-isolate-${TARGET_TRIPLET}"
)

# Suppress vcpkg post-build warnings — we only produce release libraries
# and psmisc has no public headers needed by busyq (it's tools, not a library API)
set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

# Install copyright
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
