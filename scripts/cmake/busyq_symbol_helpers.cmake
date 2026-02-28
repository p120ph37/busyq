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
#   vcpkg_build_make(OPTIONS "CPPFLAGS=-include ${_prefix_h} -Dmain=gawk_main")
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
