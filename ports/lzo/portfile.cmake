# Overlay port for lzo — fixes dead upstream download URL (oberhumer.com)
# Uses Alpine distfiles mirror instead.
vcpkg_download_distfile(ARCHIVE
    URLS
        "https://distfiles.alpinelinux.org/distfiles/v3.21/lzo-2.10.tar.gz"
        "http://www.oberhumer.com/opensource/lzo/download/lzo-2.10.tar.gz"
    FILENAME "lzo-2.10.tar.gz"
    SHA512 a3dae5e4a6b93b1f5bf7435e8ab114a9be57252e9efc5dd444947d7a2d031b0819f34bcaeb35f60b5629a01b1238d738735a64db8f672be9690d3c80094511a4
)

vcpkg_extract_source_archive(
    SOURCE_PATH
    ARCHIVE "${ARCHIVE}"
    PATCHES always_install_pc.patch
)

set(LZO_STATIC OFF)
set(LZO_SHARED OFF)
if(VCPKG_LIBRARY_LINKAGE STREQUAL static)
    set(LZO_STATIC ON)
else()
    set(LZO_SHARED ON)
endif()

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        -DENABLE_STATIC=${LZO_STATIC}
        -DENABLE_SHARED=${LZO_SHARED}
)

vcpkg_cmake_install()
vcpkg_fixup_pkgconfig()
vcpkg_copy_pdbs()

file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/share/doc")
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/libexec")
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/libexec")
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include")
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/share")

file(INSTALL "${SOURCE_PATH}/COPYING" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}" RENAME copyright)
