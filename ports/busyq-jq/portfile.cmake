vcpkg_download_distfile(ARCHIVE
    URLS "https://github.com/jqlang/jq/releases/download/jq-1.8.1/jq-1.8.1.tar.gz"
    FILENAME "jq-1.8.1.tar.gz"
    SHA512 b09d48dbeaac7b552397b75692ed7833afa72186de80d977fb1b887a14ac66c02f677acdd79f9a2736db1fd738b7ce57a39725e34846bfa21ed3728cd7adc187
)

vcpkg_extract_source_archive(SOURCE_PATH ARCHIVE "${ARCHIVE}")

# jq uses autotools.
# We do NOT pass -Dmain=jq_main in CFLAGS here because that breaks
# configure's "C compiler works" test. Instead we compile jq's main.c
# separately after the build with the rename flag.
# We DO pass yacc symbol renames here — these are harmless to configure tests
# but prevent yyerror/yyparse/yylex from colliding with bash's parser.
vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --enable-static
        --disable-shared
        --disable-maintainer-mode
        --disable-docs
        "--with-oniguruma=${CURRENT_INSTALLED_DIR}"
        "CFLAGS=-Dyyerror=jq_yyerror -Dyyparse=jq_yyparse"
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

# Build jq's main.c separately with -Dmain=jq_main to create libjqmain.a
# Use shell to invoke cc since CMAKE_C_COMPILER may not be set in portfile context
vcpkg_execute_required_process(
    COMMAND sh -c "cc -Dmain=jq_main -DHAVE_CONFIG_H -I'${JQ_BUILD_REL}' -I'${SOURCE_PATH}/src' -I'${CURRENT_INSTALLED_DIR}/include' -c '${SOURCE_PATH}/src/main.c' -o '${JQ_BUILD_REL}/jq_main.o'"
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

# Install copyright
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
