# Custom vcpkg triplet for busyq — release-only builds
#
# We never use debug artifacts (all ports produce release .a files that
# get linked into the final static binary). Skipping the debug build
# halves the build time and avoids debug-specific compilation failures.

set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME Linux)
set(VCPKG_BUILD_TYPE release)
