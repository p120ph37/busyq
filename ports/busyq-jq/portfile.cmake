include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_alpine_helpers.cmake")

busyq_alpine_source(
    PORT_DIR "${CMAKE_CURRENT_LIST_DIR}"
    OUT_SOURCE_PATH SOURCE_PATH
    USE_PATCH_CMD
)

# Detect toolchain flags FIRST, before autotools configure claims the build
# directory. vcpkg_cmake_get_vars creates a temporary cmake project in the
# build tree dir; running it early prevents it from clobbering autotools
# artifacts (config.h, version.h, libjq.a) that we need later.
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

set(JQ_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(JQ_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

# jq uses autotools.
# We do NOT pass -Dmain=jq_main in CFLAGS here because that breaks
# configure's "C compiler works" test. Instead we compile jq's main.c
# separately after the build with the rename flag.
# We DO pass yacc symbol renames here — these are harmless to configure tests
# but prevent yyerror/yyparse/yylex from colliding with bash's parser.
# Use VCPKG_C_FLAGS to append flags (preserving toolchain LTO/optimization)
# instead of overriding CFLAGS in OPTIONS which would discard them.
# vcpkg requires both C and CXX flags to be set together
string(APPEND VCPKG_C_FLAGS " -Dyyerror=jq_yyerror -Dyyparse=jq_yyparse")
string(APPEND VCPKG_CXX_FLAGS " -Dyyerror=jq_yyerror -Dyyparse=jq_yyparse")

vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --enable-static
        --disable-shared
        --disable-maintainer-mode
        --disable-docs
        "--with-oniguruma=${CURRENT_INSTALLED_DIR}"
)

vcpkg_build_make()

set(JQ_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

# Install libjq.a (autotools puts it in .libs/ under the build root)
file(GLOB JQ_STATIC_LIB
    "${JQ_BUILD_REL}/.libs/libjq.a"
    "${JQ_BUILD_REL}/src/.libs/libjq.a"
)
file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")
file(INSTALL ${JQ_STATIC_LIB} DESTINATION "${CURRENT_PACKAGES_DIR}/lib")

# Build jq's main.c separately with -Dmain=jq_main to create libjqmain.a.
# The autotools build dir still has config.h and version.h at this point.
vcpkg_execute_required_process(
    COMMAND sh -c "'${JQ_CC}' ${JQ_CFLAGS} -Dmain=jq_main -DHAVE_CONFIG_H -I'${JQ_BUILD_REL}' -I'${JQ_BUILD_REL}/src' -I'${SOURCE_PATH}' -I'${SOURCE_PATH}/src' -I'${CURRENT_INSTALLED_DIR}/include' -c '${SOURCE_PATH}/src/main.c' -o '${JQ_BUILD_REL}/jq_main.o'"
    WORKING_DIRECTORY "${JQ_BUILD_REL}"
    LOGNAME "compile-jqmain-${TARGET_TRIPLET}"
)

vcpkg_execute_required_process(
    COMMAND ar rcs "${CURRENT_PACKAGES_DIR}/lib/libjqmain.a" "${JQ_BUILD_REL}/jq_main.o"
    WORKING_DIRECTORY "${JQ_BUILD_REL}"
    LOGNAME "ar-jqmain-${TARGET_TRIPLET}"
)

# Install headers
file(INSTALL
    "${SOURCE_PATH}/src/jv.h"
    "${SOURCE_PATH}/src/jq.h"
    DESTINATION "${CURRENT_PACKAGES_DIR}/include"
)

# Suppress vcpkg post-build warnings — we only produce release libraries
set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)

# Install copyright
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
