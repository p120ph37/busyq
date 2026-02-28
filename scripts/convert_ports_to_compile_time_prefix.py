#!/usr/bin/env python3
"""
Convert busyq ports from objcopy --prefix-symbols to compile-time symbol prefixing.

This script modifies portfile.cmake files to use -include <prefix>.h instead of
objcopy --prefix-symbols, which destroys LLVM bitcode under LTO.

Changes per portfile:
1. Add include of busyq_symbol_helpers.cmake
2. Add prefix header generation (busyq_gen_prefix_header)
3. Modify build step to use -include and -Dmain=
4. Replace objcopy-based symbol isolation with simple ld -r + ar

Also updates vcpkg.json to add busyq-bash dependency.
"""

import json
import os
import re
import sys

PORTS_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "ports")

# Port configuration: (port_name, prefix, type, extra_info)
# type: 'single' = one main, 'multi' = multiple mains (keep objcopy --redefine-sym for main)
# For 'single': extra_info = entry_point_name
# For 'multi': extra_info = None (main handling preserved but objcopy --prefix-symbols removed)
PORTS = [
    # Single-main autotools ports (vcpkg_build_make)
    ("busyq-gawk", "gawk", "single", "gawk_main"),
    ("busyq-sed", "sed", "single", "sed_main"),
    ("busyq-grep", "grep", "single", "grep_main"),
    ("busyq-patch", "patch", "single", "patch_main"),
    ("busyq-tar", "tar", "single", "tar_main"),
    ("busyq-gzip", "gz", "single", "gzip_main"),
    ("busyq-xz", "xz", "single", "xz_main"),
    ("busyq-cpio", "cpio", "single", "cpio_main"),
    ("busyq-lzop", "lzop", "single", "lzop_main"),
    ("busyq-less", "less", "single", "less_main"),
    ("busyq-time", "time", "single", "time_main"),
    ("busyq-which", "which", "single", "which_main"),
    ("busyq-wget", "wget", "single", "wget_main"),
    ("busyq-lsof", "lsof", "single", "lsof_main"),
    # Custom build single-main (manual compile)
    ("busyq-bzip2", "bz", "manual_single", "bzip2_main"),
    ("busyq-dos2unix", "d2u", "manual_single", "dos2unix_main"),
    ("busyq-ed", "ed", "custom_single", "ed_main"),
    # Multi-main autotools ports
    ("busyq-bc", "bc", "multi", None),
    ("busyq-diffutils", "diff", "multi", None),
    ("busyq-findutils", "fu", "multi", None),
    ("busyq-sharutils", "shar", "multi", None),
    ("busyq-procps", "procps", "multi", None),
    ("busyq-psmisc", "psmisc", "multi", None),
    # Multi-build port
    ("busyq-zip", "zip", "zip_special", None),
]


def add_helper_include(content):
    """Add include of busyq_symbol_helpers.cmake after alpine_helpers include."""
    marker = 'include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_alpine_helpers.cmake")'
    helper = 'include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_symbol_helpers.cmake")'
    if helper in content:
        return content
    return content.replace(marker, marker + "\n" + helper)


def add_prefix_header_gen(content, prefix):
    """Add prefix header generation after vcpkg_cmake_get_vars."""
    # Find the right insertion point - after include("${cmake_vars_file}")
    insert_after = 'include("${cmake_vars_file}")'
    gen_code = f'''
# --- Generate compile-time symbol prefix header (LTO-safe) ---
set(_prefix_h "${{SOURCE_PATH}}/{prefix}_prefix.h")
busyq_gen_prefix_header({prefix} "${{_prefix_h}}")
'''
    if f"{prefix}_prefix.h" in content:
        return content
    idx = content.find(insert_after)
    if idx < 0:
        print(f"  WARNING: Could not find '{insert_after}' to insert prefix header gen")
        return content
    end = idx + len(insert_after)
    return content[:end] + gen_code + content[end:]


def convert_single_main_autotools(content, prefix, entry):
    """Convert a single-main autotools port."""
    content = add_helper_include(content)
    content = add_prefix_header_gen(content, prefix)

    # Modify vcpkg_build_make() to include prefix header and -Dmain
    # Handle both vcpkg_build_make() and vcpkg_build_make(OPTIONS ...)
    # and vcpkg_build_make(BUILD_TARGET ...)

    # Pattern: vcpkg_build_make() with no args
    content = re.sub(
        r'vcpkg_build_make\(\)',
        f'vcpkg_build_make(OPTIONS "CPPFLAGS=-include ${{_prefix_h}} -Dmain={entry}")',
        content
    )
    # Pattern: vcpkg_build_make(BUILD_TARGET target)
    content = re.sub(
        r'vcpkg_build_make\(BUILD_TARGET\s+(\w+)\)',
        rf'vcpkg_build_make(BUILD_TARGET \1 OPTIONS "CPPFLAGS=-include ${{_prefix_h}} -Dmain={entry}")',
        content
    )

    # Replace the symbol isolation section
    content = replace_symbol_isolation_simple(content, prefix)

    return content


def replace_symbol_isolation_simple(content, prefix):
    """Replace objcopy-based symbol isolation with simple ld -r + ar."""
    # Find the start of the symbol isolation section
    # Look for the sh -c script that uses objcopy
    pattern = re.compile(
        r'(# Steps? \d.*?|# Combine, prefix.*?)?'
        r'vcpkg_execute_required_process\(\s*COMMAND sh -c ".*?objcopy.*?"\s*'
        r'WORKING_DIRECTORY\s+"[^"]*"\s*'
        r'LOGNAME\s+"[^"]*"\s*\)',
        re.DOTALL
    )

    def replacement(m):
        # Extract working directory and logname from the match
        wd_match = re.search(r'WORKING_DIRECTORY\s+"([^"]*)"', m.group())
        ln_match = re.search(r'LOGNAME\s+"([^"]*)"', m.group())
        wd = wd_match.group(1) if wd_match else "${BUILD_REL}"
        ln = ln_match.group(1) if ln_match else f"combine-${{TARGET_TRIPLET}}"

        # Find the output library name from ar rcs command
        lib_match = re.search(r"ar rcs '(\$\{CURRENT_PACKAGES_DIR\}/lib/lib\w+\.a)'", m.group())
        lib_name = lib_match.group(1) if lib_match else f"${{CURRENT_PACKAGES_DIR}}/lib/lib{prefix}.a"

        return f'''# Combine objects and package (no objcopy — compile-time prefix preserves bitcode)
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e
        ld -r --whole-archive lib_raw.a -o combined.o \\
            -z muldefs 2>/dev/null \\
        || ld -r --whole-archive lib_raw.a -o combined.o
        ar rcs '{lib_name}' combined.o
    "
    WORKING_DIRECTORY "{wd}"
    LOGNAME "combine-${{TARGET_TRIPLET}}"
)'''

    # Try the pattern
    new_content, count = pattern.subn(replacement, content)
    if count > 0:
        return new_content

    # Fallback: try a simpler pattern for the objcopy section
    # Look for the block starting with the sh -c that contains objcopy
    lines = content.split('\n')
    new_lines = []
    skip_until_close = False
    paren_depth = 0
    found_replacement = False

    i = 0
    while i < len(lines):
        line = lines[i]

        # Check if this is the start of the objcopy section
        if 'objcopy' in line and 'COMMAND sh -c' in '\n'.join(lines[max(0,i-5):i+1]):
            # We're inside a vcpkg_execute_required_process with objcopy
            # Go back to find the start of the vcpkg_execute_required_process
            # Actually, let's handle this at a higher level
            pass

        new_lines.append(line)
        i += 1

    # If pattern replacement didn't work, return with a warning comment
    if count == 0:
        print(f"  WARNING: Could not auto-replace symbol isolation section")

    return new_content if count > 0 else content


def convert_multi_main_autotools(content, prefix):
    """Convert a multi-main autotools port.

    For multi-main ports, we:
    1. Add prefix header generation
    2. Build with prefix header (but NOT -Dmain since there are multiple mains)
    3. Keep objcopy --redefine-sym for main→tool_main rename (safe: single symbol)
    4. Remove objcopy --prefix-symbols (breaks bitcode)
    5. Keep ld -r + ar
    """
    content = add_helper_include(content)
    content = add_prefix_header_gen(content, prefix)

    # Modify vcpkg_build_make() to include prefix header only (no -Dmain)
    content = re.sub(
        r'vcpkg_build_make\(\)',
        f'vcpkg_build_make(OPTIONS "CPPFLAGS=-include ${{_prefix_h}}")',
        content
    )

    # Remove objcopy --prefix-symbols and the unprefix/redefine map generation
    # but KEEP objcopy --redefine-sym for main renames
    # This is complex and port-specific, so we'll handle it per-port

    return content


def update_vcpkg_json(port_dir):
    """Add busyq-bash to dependencies in vcpkg.json."""
    vcpkg_json = os.path.join(port_dir, "vcpkg.json")
    if not os.path.exists(vcpkg_json):
        print(f"  WARNING: {vcpkg_json} not found")
        return

    with open(vcpkg_json) as f:
        data = json.load(f)

    deps = data.get("dependencies", [])

    # Check if busyq-bash is already a dependency
    has_bash = False
    for dep in deps:
        if isinstance(dep, str) and dep == "busyq-bash":
            has_bash = True
        elif isinstance(dep, dict) and dep.get("name") == "busyq-bash":
            has_bash = True

    if not has_bash:
        deps.insert(0, "busyq-bash")
        data["dependencies"] = deps

        with open(vcpkg_json, "w") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
        print(f"  Added busyq-bash dependency to {vcpkg_json}")
    else:
        print(f"  busyq-bash already in {vcpkg_json}")


def main():
    # Only process vcpkg.json updates - the portfile changes are too
    # port-specific for full automation. We'll handle those individually.
    print("Updating vcpkg.json files to add busyq-bash dependency...")
    for port_name, prefix, ptype, extra in PORTS:
        port_dir = os.path.join(PORTS_DIR, port_name)
        if os.path.isdir(port_dir):
            print(f"Processing {port_name}...")
            update_vcpkg_json(port_dir)
        else:
            print(f"  WARNING: {port_dir} not found")

    print("\nDone updating vcpkg.json files.")
    print("\nPortfile conversions need to be done individually due to")
    print("port-specific symbol isolation logic.")


if __name__ == "__main__":
    main()
