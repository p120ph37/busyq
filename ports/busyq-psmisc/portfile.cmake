# busyq-psmisc portfile - uses Alpine-synced source and patches
include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_alpine_helpers.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_symbol_helpers.cmake")

busyq_alpine_source(
    PORT_DIR "${CMAKE_CURRENT_LIST_DIR}"
    OUT_SOURCE_PATH SOURCE_PATH
)

# Detect toolchain flags
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

# Only build release (debug artifacts are unused)
set(VCPKG_BUILD_TYPE release)

# --- Generate compile-time symbol prefix header (LTO-safe) ---
set(_prefix_h "${SOURCE_PATH}/psmisc_prefix.h")
busyq_gen_prefix_header(psmisc "${_prefix_h}")

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

vcpkg_build_make(OPTIONS "CPPFLAGS=-include ${_prefix_h}")

# Rename main() after the build — doing it before would break the link step
foreach(_tool killall fuser pstree)
    busyq_post_build_rename_main(${_tool} "${_prefix_h}" "${SOURCE_PATH}/src/${_tool}.c")
endforeach()

set(PSMISC_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

file(GLOB_RECURSE PSMISC_OBJS "${PSMISC_BUILD_REL}/src/*.o")
list(FILTER PSMISC_OBJS EXCLUDE REGEX "/(tests|testsuite|man|doc)/")

if(NOT PSMISC_OBJS)
    message(FATAL_ERROR "No psmisc object files found in ${PSMISC_BUILD_REL}")
endif()

busyq_package_objects(libpsmisc.a "${PSMISC_BUILD_REL}" OBJECTS ${PSMISC_OBJS})

busyq_finalize_port()
