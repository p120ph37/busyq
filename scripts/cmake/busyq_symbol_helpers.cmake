# busyq_symbol_helpers.cmake — LTO-safe compile-time symbol prefixing
#                              and object packaging helpers
#
# Replaces objcopy --prefix-symbols (which destroys LLVM bitcode) with
# a compile-time approach using -include <prefix_header>.  The header
# contains #define macros that rename collision-prone symbols at the
# preprocessor level, preserving LLVM IR for cross-project LTO.
#
# Usage in a portfile:
#
#   include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_symbol_helpers.cmake")
#
#   busyq_gen_prefix_header(gawk "${SOURCE_PATH}/gawk_prefix.h")
#
#   vcpkg_build_make(OPTIONS "CPPFLAGS=-include ${_prefix_h}")
#
#   busyq_post_build_rename_main(gawk "${_prefix_h}" "${SOURCE_PATH}/main.c")
#
#   busyq_package_objects(libgawk.a "${BUILD_REL}" OBJECTS ${GAWK_OBJS})
#
#   busyq_finalize_port()
#
# The main() rename is done AFTER the build because renaming it before
# would cause the link step to fail (undefined symbol: main).
# busyq_post_build_rename_main recompiles just the one .o file using make,
# which preserves all compiler flags and include paths from the Makefile.
#
# Requires busyq-bash to be installed (add dependency in vcpkg.json).

function(busyq_gen_prefix_header _prefix _output_file)
    set(_bash_lib_dir "${CURRENT_INSTALLED_DIR}/lib")

    vcpkg_execute_required_process(
        COMMAND sh -c "
            set -e

            # Step 1: Defined global symbols from all bash libraries
            for lib in libbash.a libbuiltins.a libreadline.a libhistory.a libglob.a libtilde.a libsh.a; do
                [ -f '${_bash_lib_dir}/'$lib ] && nm --defined-only -g '${_bash_lib_dir}/'$lib 2>/dev/null || true
            done | awk 'NF>=3 && $2~/[A-Z]/ {print $3}' | sort -u > /tmp/_bq_${_prefix}_bash_syms.txt

            # Step 2: Defined global symbols from libc (must NOT be prefixed)
            nm --defined-only -g /usr/lib/libc.a 2>/dev/null \
                | awk 'NF>=3 && $2~/[A-Z]/ {print $3}' | sort -u > /tmp/_bq_${_prefix}_libc_syms.txt

            # Exclude well-known linker/runtime symbols and main
            printf '%s\n' main _start _init _fini __libc_start_main >> /tmp/_bq_${_prefix}_libc_syms.txt
            sort -u -o /tmp/_bq_${_prefix}_libc_syms.txt /tmp/_bq_${_prefix}_libc_syms.txt

            # Step 3: Collision candidates = bash-defined minus libc-defined
            comm -23 /tmp/_bq_${_prefix}_bash_syms.txt /tmp/_bq_${_prefix}_libc_syms.txt \
                > /tmp/_bq_${_prefix}_prefix_syms.txt

            # Generate the prefix header
            {
                echo '/* Auto-generated compile-time symbol prefix header */'
                echo '/* Renames collision-prone symbols to avoid gnulib/bash conflicts */'
                echo '/* Preserves LLVM bitcode (replaces objcopy --prefix-symbols) */'
                echo '#ifndef BUSYQ_${_prefix}_PREFIX_H'
                echo '#define BUSYQ_${_prefix}_PREFIX_H'
                while IFS= read -r sym; do
                    echo \"#define \$sym ${_prefix}_\$sym\"
                done < /tmp/_bq_${_prefix}_prefix_syms.txt
                echo '#endif'
            } > '${_output_file}'

            count=\$(wc -l < /tmp/_bq_${_prefix}_prefix_syms.txt)
            echo \"Generated ${_prefix}_prefix.h with \$count symbol renames\"
        "
        WORKING_DIRECTORY "${CURRENT_BUILDTREES_DIR}"
        LOGNAME "gen-${_prefix}-prefix-${TARGET_TRIPLET}"
    )
endfunction()

# busyq_post_build_rename_main(<tool> <prefix_header> <source> [<source2> ...])
#
# Recompiles a single source file AFTER the build to rename main() to
# <tool>_main. Must be called AFTER vcpkg_build_make() — the initial build
# needs a real main() for the link step to succeed.
#
# Takes a list of candidate source files and uses the first one that exists
# (same semantics as the old busyq_rename_main).
#
# Implementation: touches the source to invalidate make's dependency tracking,
# then runs `make <target>.o` with -Dmain=<tool>_main added to CPPFLAGS.
# This preserves all compiler flags, include paths, etc. from the Makefile.
#
# Automake may mangle object file names when per-program variables exist
# (e.g., src/main.c → src/xz-main.o). We always glob the build tree to
# find the actual .o name rather than guessing from the source filename.
# Works for both recursive make (Makefile per subdirectory) and
# non-recursive make (single top-level Makefile).
function(busyq_post_build_rename_main _tool _prefix_h)
    # Find the first existing candidate source file
    set(_source "")
    foreach(_file ${ARGN})
        if(EXISTS "${_file}")
            set(_source "${_file}")
            break()
        endif()
    endforeach()
    if(NOT _source)
        message(FATAL_ERROR "busyq_post_build_rename_main(${_tool}): no candidate source files found: ${ARGN}")
    endif()

    # Determine build subdirectory from source path relative to SOURCE_PATH
    file(RELATIVE_PATH _rel "${SOURCE_PATH}" "${_source}")
    get_filename_component(_dir "${_rel}" DIRECTORY)
    get_filename_component(_name "${_rel}" NAME_WE)

    set(_build_rel "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

    # Find the actual .o file in the build tree.  Automake per-program
    # variables cause name mangling (main.c → xz-main.o), so we glob
    # for both the plain name and the *-<name>.o pattern.
    if(_dir)
        set(_search_dir "${_build_rel}/${_dir}")
    else()
        set(_search_dir "${_build_rel}")
    endif()

    file(GLOB _obj_matches
        "${_search_dir}/${_name}.o"
        "${_search_dir}/*-${_name}.o"
    )

    # Determine working directory and target based on build layout
    if(_dir AND EXISTS "${_build_rel}/${_dir}/Makefile")
        # Recursive make: run from subdirectory
        set(_work_dir "${_build_rel}/${_dir}")
        if(_obj_matches)
            list(GET _obj_matches 0 _obj)
            get_filename_component(_target "${_obj}" NAME)
        else()
            set(_target "${_name}.o")
        endif()
    else()
        # Non-recursive make: run from build root
        set(_work_dir "${_build_rel}")
        if(_obj_matches)
            list(GET _obj_matches 0 _obj)
            file(RELATIVE_PATH _target "${_build_rel}" "${_obj}")
        elseif(_dir)
            set(_target "${_dir}/${_name}.o")
        else()
            set(_target "${_name}.o")
        endif()
    endif()

    # Touch source to force make to rebuild this .o file
    file(TOUCH "${_source}")

    vcpkg_execute_required_process(
        COMMAND make "${_target}"
            "CPPFLAGS=-include ${_prefix_h} -Dmain=${_tool}_main"
            V=1
        WORKING_DIRECTORY "${_work_dir}"
        LOGNAME "rename-main-${_tool}-${TARGET_TRIPLET}"
    )
endfunction()

# busyq_package_objects(<output_lib> <working_dir> OBJECTS <obj1> [<obj2> ...]
#                       [KEEP_GLOBAL <pattern>])
#
# Combines object files into a single static library with all internal
# symbols localized (hidden).  Only symbols matching KEEP_GLOBAL remain
# global, preventing cross-port symbol collisions at final link time.
#
# Steps:
#   1. ar rcs → temporary raw archive
#   2. ld -r --whole-archive → single relocatable object
#   3. llvm-objcopy --keep-global-symbol → localize internals
#   4. ar rcs → final library in ${CURRENT_PACKAGES_DIR}/lib/
#
# KEEP_GLOBAL defaults to '*_main'.  Coreutils passes
# 'single_binary_main_*' instead.
function(busyq_package_objects _output_lib _working_dir)
    cmake_parse_arguments(PARSE_ARGV 2 ARG "" "KEEP_GLOBAL" "OBJECTS")

    if(NOT ARG_OBJECTS)
        message(FATAL_ERROR "busyq_package_objects(${_output_lib}): OBJECTS list is empty")
    endif()

    if(NOT ARG_KEEP_GLOBAL)
        set(ARG_KEEP_GLOBAL "*_main")
    endif()

    file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

    vcpkg_execute_required_process(
        COMMAND ar rcs "${_working_dir}/lib_raw.a" ${ARG_OBJECTS}
        WORKING_DIRECTORY "${_working_dir}"
        LOGNAME "ar-raw-${PORT}-${TARGET_TRIPLET}"
    )

    vcpkg_execute_required_process(
        COMMAND sh -c "
            set -e
            ld -r --whole-archive lib_raw.a -o combined.o \
                -z muldefs 2>/dev/null \
            || ld -r --whole-archive lib_raw.a -o combined.o
            llvm-objcopy --wildcard --keep-global-symbol='${ARG_KEEP_GLOBAL}' combined.o
            ar rcs '${CURRENT_PACKAGES_DIR}/lib/${_output_lib}' combined.o
        "
        WORKING_DIRECTORY "${_working_dir}"
        LOGNAME "combine-${PORT}-${TARGET_TRIPLET}"
    )
endfunction()

# busyq_finalize_port([COPYRIGHT <file>])
#
# Standard tail-end boilerplate for busyq tool ports:
#   - Suppresses vcpkg warnings about mismatched binary counts and empty
#     include folders (tools produce no headers or debug artifacts)
#   - Installs the copyright/license file
#
# COPYRIGHT defaults to ${SOURCE_PATH}/COPYING.
function(busyq_finalize_port)
    cmake_parse_arguments(PARSE_ARGV 0 ARG "" "COPYRIGHT" "")

    set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled PARENT_SCOPE)
    set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled PARENT_SCOPE)

    if(ARG_COPYRIGHT)
        vcpkg_install_copyright(FILE_LIST "${ARG_COPYRIGHT}")
    else()
        vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
    endif()
endfunction()
