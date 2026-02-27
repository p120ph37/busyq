vcpkg_download_distfile(ARCHIVE
    URLS "https://ftpmirror.gnu.org/gnu/time/time-1.9.tar.gz"
         "https://mirrors.kernel.org/gnu/time/time-1.9.tar.gz"
         "https://ftp.gnu.org/gnu/time/time-1.9.tar.gz"
    FILENAME "time-1.9.tar.gz"
    SHA512 0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
)

vcpkg_extract_source_archive(SOURCE_PATH ARCHIVE "${ARCHIVE}")

# Detect toolchain flags
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

set(TIME_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(TIME_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

set(ENV{FORCE_UNSAFE_CONFIGURE} "1")

vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --disable-nls
)

vcpkg_build_make()

set(TIME_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# --- Symbol isolation ---
# GNU time embeds gnulib, so we need full symbol isolation.

# Step 1: Collect object files
file(GLOB TIME_OBJS "${TIME_BUILD_REL}/*.o")
file(GLOB TIME_LIB_OBJS "${TIME_BUILD_REL}/lib/*.o")
list(APPEND TIME_OBJS ${TIME_LIB_OBJS})

if(NOT TIME_OBJS)
    message(FATAL_ERROR "No time object files found in ${TIME_BUILD_REL}")
endif()

# Step 1a: Pack into temporary archive
vcpkg_execute_required_process(
    COMMAND ar rcs "${TIME_BUILD_REL}/libtime_raw.a" ${TIME_OBJS}
    WORKING_DIRECTORY "${TIME_BUILD_REL}"
    LOGNAME "ar-raw-${TARGET_TRIPLET}"
)

# Steps 2-7: Combine, prefix, unprefix, rename
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e

        # Combine into one relocatable object
        ld -r --whole-archive libtime_raw.a -o time_combined.o \
            -z muldefs 2>/dev/null \
        || ld -r --whole-archive libtime_raw.a -o time_combined.o

        # Record undefined symbols
        nm -u time_combined.o | sed 's/.* //' | sort -u > undef_syms.txt

        # Prefix all symbols with time_
        objcopy --prefix-symbols=time_ time_combined.o

        # Generate redefine map to unprefix external deps
        sed 's/.*/time_& &/' undef_syms.txt > redefine.map

        # Rename time_main -> time_main (entry point)
        echo 'time_main time_main' >> redefine.map

        objcopy --redefine-syms=redefine.map time_combined.o

        # Package into final archive
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libtime.a' time_combined.o
    "
    WORKING_DIRECTORY "${TIME_BUILD_REL}"
    LOGNAME "symbol-isolate-${TARGET_TRIPLET}"
)

set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
