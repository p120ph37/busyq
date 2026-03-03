# busyq-iproute2: ip command from iproute2, based on alpine iproute2-minimal
#
# Builds only the ip command (not tc, bridge, ss, etc.).
# Uses direct compilation rather than the iproute2 Makefile to avoid
# running configure and to maintain full control over compiler flags.
#
# iproute2 does NOT embed gnulib, but has generic symbol names (matches,
# json, timestamp, force, etc.) that require compile-time prefixing.
#
# The ip command uses netlink sockets (AF_NETLINK) to communicate with
# the kernel.  External dependency: libmnl (for extended error acks
# and generic netlink support).
#
# iproute2 has built-in static linking support: when NO_SHARED_LIBS is
# defined, a stub dlfcn.h provides fake dlopen/dlsym that resolves
# link type plugins from a compiled-in static-syms.h table.

include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_alpine_helpers.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_symbol_helpers.cmake")

busyq_alpine_source(
    PORT_DIR "${CMAKE_CURRENT_LIST_DIR}"
    OUT_SOURCE_PATH SOURCE_PATH
    USE_PATCH_CMD
)

vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

set(VCPKG_BUILD_TYPE release)

# --- Generate compile-time symbol prefix header (LTO-safe) ---
# iproute2 has generic names (matches, json, timestamp, force, etc.)
# that could collide with other packages.
set(_prefix_h "${SOURCE_PATH}/ip_prefix.h")
busyq_gen_prefix_header(ip "${_prefix_h}")

set(IP_CC "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
set(IP_CFLAGS "${VCPKG_DETECTED_CMAKE_C_FLAGS} ${VCPKG_DETECTED_CMAKE_C_FLAGS_RELEASE}")

set(IP_BUILD_DIR "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")
file(MAKE_DIRECTORY "${IP_BUILD_DIR}")
file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib")

# Find libmnl via installed headers/libs
set(_mnl_inc "${CURRENT_INSTALLED_DIR}/include")
set(_mnl_lib "${CURRENT_INSTALLED_DIR}/lib")

# --- Build iproute2 lib/ and ip/ via direct compilation ---
# We bypass iproute2's configure/Makefile and compile directly to maintain
# full control over flags and avoid build system dependencies.
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e

        SRC='${SOURCE_PATH}'
        CC='${IP_CC}'
        BASE_CFLAGS='${IP_CFLAGS}'

        # Common compile flags
        CFLAGS=\"\$BASE_CFLAGS -D_GNU_SOURCE -DHAVE_SETNS \\
            -DHAVE_HANDLE_AT -DHAVE_LIBMNL \\
            -DNO_SHARED_LIBS \\
            -I\$SRC/include -I\$SRC/include/uapi \\
            -I${_mnl_inc} \\
            -include ${_prefix_h}\"

        # Generate version.h if not present
        if [ ! -f \"\$SRC/include/version.h\" ]; then
            echo 'static const char version[] = \"${ALPINE_PKGVER}\";' > \"\$SRC/include/version.h\"
        fi

        # Generate config.h stub (configure normally creates this)
        cat > \"\$SRC/include/config.h\" <<CONFEOF
/* Generated for busyq static build */
#define HAVE_SETNS 1
#define HAVE_HANDLE_AT 1
#define HAVE_LIBMNL 1
CONFEOF

        # --- Phase 1: Compile lib/*.c ---
        echo 'Compiling iproute2 lib/'
        for f in \$SRC/lib/*.c; do
            name=\$(basename \$f .c)
            # Skip files that need optional deps we don't have
            case \$name in
                bpf_glue|bpf_legacy) continue ;;  # needs libelf/libbpf
                selinux) continue ;;               # needs libselinux
            esac
            \$CC \$CFLAGS -c \$f -o lib_\$name.o 2>/dev/null || {
                echo \"Warning: skipping lib/\$name.c (compile failed)\" >&2
            }
        done

        # --- Phase 2: Generate static-syms.h for static link type resolution ---
        # iproute2's ip command uses dlsym() to find link type handlers.
        # In static builds, a stub dlfcn.h routes to _dlsym() which uses
        # this generated table.
        echo 'Generating static-syms.h'
        {
            echo '/* Auto-generated symbol table for static ip build */'
            echo 'static struct sym_entry {'
            echo '    const char *name;'
            echo '    void *sym;'
            echo '} sym_table[] = {'
            for f in \$SRC/ip/iplink_*.c; do
                grep -o '[a-z_]*_link_util' \$f 2>/dev/null | sort -u | while read sym; do
                    echo \"    { \\\"\\$sym\\\", &\\$sym },\"
                done
            done
            echo '    { 0, 0 }'
            echo '};'
        } > \$SRC/ip/static-syms.h

        # --- Phase 3: Compile ip/*.c ---
        echo 'Compiling iproute2 ip/'
        for f in \$SRC/ip/*.c; do
            name=\$(basename \$f .c)
            # Skip files that need optional deps
            case \$name in
                ipvrf) continue ;;  # needs libcap
            esac
            EXTRA=''
            # ip.c gets -Dmain=ip_main for entry point rename
            if [ \$name = 'ip' ]; then
                EXTRA='-Dmain=ip_main'
            fi
            \$CC \$CFLAGS \$EXTRA -c \$f -o ip_\$name.o 2>/dev/null || {
                echo \"Warning: skipping ip/\$name.c (compile failed)\" >&2
            }
        done

        echo 'Compilation complete'
    "
    WORKING_DIRECTORY "${IP_BUILD_DIR}"
    LOGNAME "compile-iproute2-${TARGET_TRIPLET}"
)

# --- Collect and package objects ---
file(GLOB IP_OBJS "${IP_BUILD_DIR}/*.o")

if(NOT IP_OBJS)
    message(FATAL_ERROR "No iproute2 object files found in ${IP_BUILD_DIR}")
endif()

busyq_package_objects(libiproute2.a "${IP_BUILD_DIR}" OBJECTS ${IP_OBJS})

busyq_finalize_port()
