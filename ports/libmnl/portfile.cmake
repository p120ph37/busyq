# libmnl: Minimalistic Netlink library
#
# Small userspace library oriented to Netlink developers.  Provides helpers
# for constructing and parsing Netlink messages.  Used by iproute2's ip command
# for extended error acknowledgments and Generic Netlink support.
#
# This is a plain library dependency (not a busyq tool port), similar to lzo.
# No symbol isolation needed -- libmnl_ prefixed symbols are unique.

include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_alpine_helpers.cmake")

busyq_alpine_source(
    PORT_DIR "${CMAKE_CURRENT_LIST_DIR}"
    OUT_SOURCE_PATH SOURCE_PATH
)

vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

set(VCPKG_BUILD_TYPE release)

# libmnl uses autotools
vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --disable-shared
        --enable-static
)

vcpkg_build_make()
vcpkg_install_make()

# Remove unnecessary files
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug")
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/share/man")

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")

set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)
