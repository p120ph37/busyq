vcpkg_download_distfile(ARCHIVE
    URLS "https://github.com/jqlang/jq/releases/download/jq-1.8.1/jq-1.8.1.tar.gz"
    FILENAME "jq-1.8.1.tar.gz"
    SHA512 0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
)

vcpkg_extract_source_archive(SOURCE_PATH ARCHIVE "${ARCHIVE}")

# Find oniguruma from vcpkg
find_path(ONIG_INCLUDE_DIR oniguruma.h PATHS "${CURRENT_INSTALLED_DIR}/include" NO_DEFAULT_PATH)
find_library(ONIG_LIBRARY onig PATHS "${CURRENT_INSTALLED_DIR}/lib" NO_DEFAULT_PATH)

# jq uses autotools
vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --enable-static
        --disable-shared
        --disable-maintainer-mode
        --disable-docs
        "--with-oniguruma=${CURRENT_INSTALLED_DIR}"
    OPTIONS_RELEASE
        "CFLAGS=-Dmain=jq_main -ffunction-sections -fdata-sections -Oz -DNDEBUG"
    OPTIONS_DEBUG
        "CFLAGS=-Dmain=jq_main -g"
)

vcpkg_build_make()

# Install libjq
file(GLOB JQ_STATIC_LIB "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel/src/.libs/libjq.a")
file(INSTALL ${JQ_STATIC_LIB} DESTINATION "${CURRENT_PACKAGES_DIR}/lib")

# Install jq main object (contains jq_main)
# The jq binary's main.o is compiled with -Dmain=jq_main, so we can extract it
# or simply install the whole jq objects. Since jq binary links libjq + main.c,
# we need main.c's object.
file(GLOB JQ_MAIN_OBJ "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel/src/jq-main.o")
if(NOT JQ_MAIN_OBJ)
    # Autotools may name it differently
    file(GLOB JQ_MAIN_OBJ "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel/src/main.o")
endif()
if(JQ_MAIN_OBJ)
    # Create a static lib from the main object for easy linking
    vcpkg_execute_required_process(
        COMMAND ar rcs "${CURRENT_PACKAGES_DIR}/lib/libjqmain.a" ${JQ_MAIN_OBJ}
        WORKING_DIRECTORY "${CURRENT_BUILDTREES_DIR}"
        LOGNAME "ar-jqmain-${TARGET_TRIPLET}"
    )
endif()

# Install headers
file(INSTALL
    "${SOURCE_PATH}/src/jv.h"
    "${SOURCE_PATH}/src/jq.h"
    DESTINATION "${CURRENT_PACKAGES_DIR}/include"
)

# Install copyright
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
