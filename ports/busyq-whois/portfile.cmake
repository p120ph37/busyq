# busyq-whois: minimal standalone whois client implementation
# No external source download needed -- whois.c is shipped in the port directory.
# No symbol isolation needed -- no gnulib, no symbol collisions.

vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

# Only build release (debug artifacts are unused)
set(VCPKG_BUILD_TYPE release)

set(WHOIS_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(WHOIS_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

set(WHOIS_BUILD_DIR "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")
file(MAKE_DIRECTORY "${WHOIS_BUILD_DIR}")

# Compile whois.c with -Dmain=whois_main to rename the entry point.
# No symbol isolation needed since this is a standalone implementation
# with no gnulib or other colliding symbols.
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e
        '${WHOIS_CC}' ${WHOIS_CFLAGS} -Dmain=whois_main \
            -c '${CURRENT_PORT_DIR}/whois.c' \
            -o whois.o
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libwhois.a' whois.o
    "
    WORKING_DIRECTORY "${WHOIS_BUILD_DIR}"
    LOGNAME "build-whois-${TARGET_TRIPLET}"
)

# Suppress vcpkg post-build warnings
set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

# Install copyright (MIT license, embedded in source)
file(WRITE "${CURRENT_PACKAGES_DIR}/share/${PORT}/copyright"
"MIT License

Copyright (c) 2025 busyq contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the \"Software\"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
")
