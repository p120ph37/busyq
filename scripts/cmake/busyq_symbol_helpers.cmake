# busyq_symbol_helpers.cmake — LTO-safe compile-time symbol prefixing
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
# then runs `make <basename>.o` with -Dmain=<tool>_main added to CPPFLAGS.
# This preserves all compiler flags, include paths, etc. from the Makefile.
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
    if(_dir)
        set(_work_dir "${_build_rel}/${_dir}")
    else()
        set(_work_dir "${_build_rel}")
    endif()

    # Touch source to force make to rebuild this .o file
    file(TOUCH "${_source}")

    vcpkg_execute_required_process(
        COMMAND make "${_name}.o"
            "CPPFLAGS=-include ${_prefix_h} -Dmain=${_tool}_main"
            V=1
        WORKING_DIRECTORY "${_work_dir}"
        LOGNAME "rename-main-${_tool}-${TARGET_TRIPLET}"
    )
endfunction()
