# busyq-util-linux: util-linux tools built as a static library
#
# Builds a selected subset of util-linux as a single libutillinux.a for busyq.
# Each tool's main() is renamed to <tool>_main via post-build recompilation.
# Symbol prefixing prevents collisions with bash/coreutils gnulib symbols.
#
# Tools included (40): cal, chrt, col, colcrt, colrm, column, fallocate,
# flock, getopt, hardlink, hexdump, ionice, ipcmk, ipcrm, ipcs, logger,
# look, lscpu, lsns, mcookie, mesg, more, mountpoint, namei, nologin,
# nsenter, prlimit, rename, renice, rev, script, scriptlive, scriptreplay,
# setsid, taskset, ul, unshare, uuidgen, uuidparse, whereis
#
# Not included: disk/partition tools (fdisk, mount, etc.), login/PAM tools
# (login, su, etc.), utmp-dependent tools (last, wall, write).

include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_alpine_helpers.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_symbol_helpers.cmake")

busyq_alpine_source(
    PORT_DIR "${CMAKE_CURRENT_LIST_DIR}"
    OUT_SOURCE_PATH SOURCE_PATH
)

# musl lacks <sys/ttydefaults.h>; copy Alpine's standalone version
file(COPY "${CURRENT_PORT_DIR}/ttydefaults.h" DESTINATION "${SOURCE_PATH}/include")

# Detect toolchain flags
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

set(VCPKG_BUILD_TYPE release)

# --- Generate compile-time symbol prefix header (LTO-safe) ---
set(_prefix_h "${SOURCE_PATH}/ul_prefix.h")
busyq_gen_prefix_header(ul "${_prefix_h}")

set(ENV{FORCE_UNSAFE_CONFIGURE} "1")

# Configure with only the tools we want.  --disable-all-programs starts
# from a clean slate; each --enable-<tool> adds back one command.
vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --disable-all-programs
        # Internal libraries needed by our tools
        --enable-libuuid
        --enable-libsmartcols
        # misc-utils
        --enable-cal
        --enable-flock
        --enable-getopt
        --enable-hardlink
        --enable-logger
        --enable-look
        --enable-lscpu
        --enable-mcookie
        --enable-namei
        --enable-rename
        --enable-uuidgen
        --enable-uuidparse
        --enable-whereis
        # sys-utils
        --enable-chrt
        --enable-fallocate
        --enable-ionice
        --enable-ipcmk
        --enable-ipcrm
        --enable-ipcs
        --enable-lsns
        --enable-mountpoint
        --enable-nsenter
        --enable-prlimit
        --enable-renice
        --enable-setsid
        --enable-taskset
        --enable-unshare
        # text-utils
        --enable-col
        --enable-colcrt
        --enable-colrm
        --enable-column
        --enable-hexdump
        --enable-more
        --enable-rev
        --enable-ul
        # term-utils
        --enable-mesg
        --enable-script
        --enable-scriptlive
        --enable-scriptreplay
        # login-utils (just nologin — no PAM/utmp needed)
        --enable-nologin
        # Disable all optional dependencies we don't need
        --disable-nls
        --disable-tls
        --disable-makeinstall-setuid
        --disable-makeinstall-chown
        --disable-asciidoc
        --without-systemd
        --without-udev
        --without-python
        --without-selinux
        --without-audit
        --without-smack
        --without-econf
        --without-btrfs
        --without-readline
        --without-cap-ng
        --without-user
        --without-utempter
        --without-ncursesw
)

vcpkg_build_make(OPTIONS "CPPFLAGS=-include ${_prefix_h}")

# --- Post-build: rename each tool's main() to <tool>_main ---
# Each entry: tool_name|path/to/main_source.c (relative to SOURCE_PATH)
set(UL_TOOL_SOURCES
    "cal|misc-utils/cal.c"
    "chrt|sys-utils/chrt.c"
    "col|text-utils/col.c"
    "colcrt|text-utils/colcrt.c"
    "colrm|text-utils/colrm.c"
    "column|text-utils/column.c"
    "fallocate|sys-utils/fallocate.c"
    "flock|misc-utils/flock.c"
    "getopt|misc-utils/getopt.c"
    "hardlink|misc-utils/hardlink.c"
    "hexdump|text-utils/hexdump.c"
    "ionice|sys-utils/ionice.c"
    "ipcmk|sys-utils/ipcmk.c"
    "ipcrm|sys-utils/ipcrm.c"
    "ipcs|sys-utils/ipcs.c"
    "logger|misc-utils/logger.c"
    "look|misc-utils/look.c"
    "lscpu|sys-utils/lscpu.c"
    "lsns|sys-utils/lsns.c"
    "mcookie|misc-utils/mcookie.c"
    "mesg|term-utils/mesg.c"
    "more|text-utils/more.c"
    "mountpoint|sys-utils/mountpoint.c"
    "namei|misc-utils/namei.c"
    "nologin|login-utils/nologin.c"
    "nsenter|sys-utils/nsenter.c"
    "prlimit|sys-utils/prlimit.c"
    "rename|misc-utils/rename.c"
    "renice|sys-utils/renice.c"
    "rev|text-utils/rev.c"
    "script|term-utils/script.c"
    "scriptlive|term-utils/scriptlive.c"
    "scriptreplay|term-utils/scriptreplay.c"
    "setsid|sys-utils/setsid.c"
    "taskset|sys-utils/taskset.c"
    "ul|text-utils/ul.c"
    "unshare|sys-utils/unshare.c"
    "uuidgen|misc-utils/uuidgen.c"
    "uuidparse|misc-utils/uuidparse.c"
    "whereis|misc-utils/whereis.c"
)

foreach(_entry ${UL_TOOL_SOURCES})
    string(REPLACE "|" ";" _parts "${_entry}")
    list(GET _parts 0 _name)
    list(GET _parts 1 _src)
    busyq_post_build_rename_main("${_name}" "${_prefix_h}" "${SOURCE_PATH}/${_src}")
endforeach()

# --- Collect object files ---
set(UL_BUILD_REL "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

file(GLOB_RECURSE UL_OBJS
    "${UL_BUILD_REL}/lib/*.o"
    "${UL_BUILD_REL}/libuuid/src/*.o"
    "${UL_BUILD_REL}/libsmartcols/src/*.o"
    "${UL_BUILD_REL}/misc-utils/*.o"
    "${UL_BUILD_REL}/sys-utils/*.o"
    "${UL_BUILD_REL}/text-utils/*.o"
    "${UL_BUILD_REL}/term-utils/*.o"
    "${UL_BUILD_REL}/login-utils/*.o"
)
# Exclude test files
list(FILTER UL_OBJS EXCLUDE REGEX "/(tests|test_).*\\.o$")

if(NOT UL_OBJS)
    message(FATAL_ERROR "No object files found in ${UL_BUILD_REL}")
endif()

busyq_package_objects(libutillinux.a "${UL_BUILD_REL}" OBJECTS ${UL_OBJS})

busyq_finalize_port()
