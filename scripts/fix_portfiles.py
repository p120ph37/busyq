#!/usr/bin/env python3
"""Fix portfiles that lost their object collection steps during conversion."""

import os
import re

PORTS_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "ports")

# For each broken port, define the object collection section that needs to be
# re-inserted. Each entry: (port_name, build_var, obj_patterns, exclusion, lib_name)
SINGLE_MAIN_FIXES = {
    "busyq-gawk": {
        "build_var": "GAWK_BUILD_REL",
        "obj_var": "GAWK_OBJS",
        "glob_paths": ['"${GAWK_BUILD_REL}/*.o"'],
        "glob_type": "GLOB_RECURSE",
        "exclusions": '"/(tests|test|extension|extras)/"',
        "raw_archive": "libgawk_raw.a",
        "lib_name": "libgawk.a",
    },
    "busyq-sed": {
        "build_var": "SED_BUILD_REL",
        "obj_var": "SED_OBJS",
        "glob_paths": ['"${SED_BUILD_REL}/sed/*.o"', '"${SED_BUILD_REL}/lib/*.o"'],
        "glob_type": "GLOB_RECURSE",
        "exclusions": '"/(tests|gnulib-tests)/"',
        "raw_archive": "libsed_raw.a",
        "lib_name": "libsed.a",
    },
    "busyq-grep": {
        "build_var": "GREP_BUILD_REL",
        "obj_var": "GREP_OBJS",
        "glob_paths": ['"${GREP_BUILD_REL}/src/*.o"', '"${GREP_BUILD_REL}/lib/*.o"'],
        "glob_type": "GLOB_RECURSE",
        "exclusions": '"/(tests|gnulib-tests)/"',
        "raw_archive": "libgrep_raw.a",
        "lib_name": "libgrep.a",
    },
    "busyq-patch": {
        "build_var": "PATCH_BUILD_REL",
        "obj_var": "PATCH_OBJS",
        "glob_paths": ['"${PATCH_BUILD_REL}/src/*.o"', '"${PATCH_BUILD_REL}/lib/*.o"'],
        "glob_type": "GLOB_RECURSE",
        "exclusions": '"/(tests|gnulib-tests)/"',
        "raw_archive": "libpatch_raw.a",
        "lib_name": "libpatch.a",
    },
    "busyq-less": {
        "build_var": "LESS_BUILD_REL",
        "obj_var": "LESS_OBJS",
        "glob_paths": ['"${LESS_BUILD_REL}/*.o"'],
        "glob_type": "GLOB",
        "exclusions": None,
        "raw_archive": "libless_raw.a",
        "lib_name": "libless.a",
    },
    "busyq-which": {
        "build_var": "WHICH_BUILD_REL",
        "obj_var": "WHICH_OBJS",
        "glob_paths": ['"${WHICH_BUILD_REL}/*.o"'],
        "glob_type": "GLOB",
        "exclusions": None,
        "raw_archive": "libwhich_raw.a",
        "lib_name": "libwhich.a",
        "extra_glob": 'file(GLOB WHICH_LIB_OBJS "${WHICH_BUILD_REL}/lib/*.o")\nlist(APPEND WHICH_OBJS ${WHICH_LIB_OBJS})',
    },
    "busyq-wget": {
        "build_var": "WGET_BUILD_REL",
        "obj_var": "WGET_OBJS",
        "glob_paths": ['"${WGET_BUILD_REL}/src/*.o"', '"${WGET_BUILD_REL}/lib/*.o"'],
        "glob_type": "GLOB_RECURSE",
        "exclusions": '"/(tests|testenv|fuzz)/"',
        "raw_archive": "libwget_raw.a",
        "lib_name": "libwget.a",
    },
    "busyq-lsof": {
        "build_var": "LSOF_BUILD_REL",
        "obj_var": "LSOF_OBJS",
        "glob_paths": ['"${LSOF_BUILD_REL}/src/*.o"', '"${LSOF_BUILD_REL}/lib/*.o"'],
        "glob_type": "GLOB_RECURSE",
        "exclusions": '"/(tests|testsuite|man|doc)/"',
        "raw_archive": "liblsof_raw.a",
        "lib_name": "liblsof.a",
    },
}


def fix_port(port_name, config):
    pf = os.path.join(PORTS_DIR, port_name, "portfile.cmake")
    with open(pf) as f:
        content = f.read()

    # Check if already has object collection
    if "GLOB" in content and "ar rcs" in content and content.count("ar rcs") >= 2:
        print(f"  {port_name}: already has object collection, skipping")
        return

    build_var = config["build_var"]
    obj_var = config["obj_var"]
    glob_type = config["glob_type"]
    exclusions = config.get("exclusions")
    raw_archive = config["raw_archive"]
    lib_name = config["lib_name"]
    extra_glob = config.get("extra_glob", "")
    glob_paths = config["glob_paths"]

    # Build the object collection section
    glob_lines = "\n    ".join(glob_paths)
    obj_section = f"""
# Collect all object files from the build
file({glob_type} {obj_var}
    {glob_lines}
)"""

    if exclusions:
        obj_section += f'\nlist(FILTER {obj_var} EXCLUDE REGEX {exclusions})'

    if extra_glob:
        obj_section += f'\n{extra_glob}'

    obj_section += f"""

if(NOT {obj_var})
    message(FATAL_ERROR "No object files found in ${{{build_var}}}")
endif()

# Pack into temporary archive (needed for ld -r --whole-archive)
vcpkg_execute_required_process(
    COMMAND ar rcs "${{{build_var}}}/{raw_archive}" ${{{obj_var}}}
    WORKING_DIRECTORY "${{{build_var}}}"
    LOGNAME "ar-raw-${{{config.get('triplet_var', 'TARGET_TRIPLET')}}}"
)
"""

    # Find where to insert: before "# Combine objects and package"
    insert_marker = "# Combine objects and package"
    idx = content.find(insert_marker)
    if idx < 0:
        print(f"  {port_name}: WARNING - could not find insertion point")
        return

    # Also fix the raw archive name in the combine step to match
    content = content.replace("lib_raw.a", raw_archive)

    # Insert the object collection section
    new_content = content[:idx] + obj_section + content[idx:]

    with open(pf, "w") as f:
        f.write(new_content)
    print(f"  {port_name}: fixed - added object collection")


def main():
    for port_name, config in SINGLE_MAIN_FIXES.items():
        fix_port(port_name, config)

    # Also need to fix diffutils which lost its ar rcs step
    fix_diffutils()


def fix_diffutils():
    """Fix diffutils which needs both object collection and main renames."""
    pf = os.path.join(PORTS_DIR, "busyq-diffutils", "portfile.cmake")
    with open(pf) as f:
        content = f.read()

    # Diffutils needs:
    # 1. Object collection
    # 2. Per-tool main rename (objcopy --redefine-sym for individual mains)
    # 3. Raw archive creation
    # 4. Combine + entry point renames

    if "GLOB" in content and content.count("ar rcs") >= 2:
        print(f"  busyq-diffutils: already has object collection, skipping")
        return

    # Find the combine section and replace it with the full section
    old_section_start = content.find("# --- Symbol isolation ---")
    old_section_end = content.find("# Suppress vcpkg post-build")

    if old_section_start < 0 or old_section_end < 0:
        # Try alternate markers
        old_section_start = content.find("# Step 1a: Rename main")
        if old_section_start < 0:
            old_section_start = content.find("# Combine objects and rename")
        if old_section_start < 0:
            print("  busyq-diffutils: could not find section markers")
            return

    new_section = """# --- Symbol isolation ---
# diffutils has four separate commands (diff, cmp, diff3, sdiff), each with
# its own main(). Compile-time prefix header handles gnulib collisions.
# Individual main renames use objcopy --redefine-sym (safe for single symbols).

# Collect all object files from the build
file(GLOB_RECURSE DU_OBJS
    "${DU_BUILD_REL}/src/*.o"
    "${DU_BUILD_REL}/lib/*.o"
)
list(FILTER DU_OBJS EXCLUDE REGEX "/(tests|gnulib-tests)/")

if(NOT DU_OBJS)
    message(FATAL_ERROR "No diffutils object files found in ${DU_BUILD_REL}")
endif()

# Rename main in each tool's object file before combining
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e
        for tool in diff cmp diff3 sdiff; do
            obj='${DU_BUILD_REL}/src/'\\\"\\$tool\\\".o
            if [ -f \\\"\\$obj\\\" ]; then
                objcopy --redefine-sym main=\\\"\\${tool}_main\\\" \\\"\\$obj\\\"
            fi
        done
    "
    WORKING_DIRECTORY "${DU_BUILD_REL}"
    LOGNAME "rename-mains-${TARGET_TRIPLET}"
)

# Pack into temporary archive
vcpkg_execute_required_process(
    COMMAND ar rcs "${DU_BUILD_REL}/libdiffutils_raw.a" ${DU_OBJS}
    WORKING_DIRECTORY "${DU_BUILD_REL}"
    LOGNAME "ar-raw-${TARGET_TRIPLET}"
)

# Combine objects and package (no --prefix-symbols — compile-time prefix preserves bitcode)
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e
        ld -r --whole-archive libdiffutils_raw.a -o combined.o \\
            -z muldefs 2>/dev/null \\
        || ld -r --whole-archive libdiffutils_raw.a -o combined.o
        ar rcs '${CURRENT_PACKAGES_DIR}/lib/libdiffutils.a' combined.o
    "
    WORKING_DIRECTORY "${DU_BUILD_REL}"
    LOGNAME "combine-${TARGET_TRIPLET}"
)

"""

    new_content = content[:old_section_start] + new_section + content[old_section_end:]
    with open(pf, "w") as f:
        f.write(new_content)
    print(f"  busyq-diffutils: fixed - rewrote symbol isolation section")


if __name__ == "__main__":
    main()
