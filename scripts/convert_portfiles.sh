#!/bin/sh
# Convert all portfiles from objcopy --prefix-symbols to compile-time symbol prefixing.
# This script rewrites the symbol isolation sections in each portfile.
#
# For single-main ports: adds -include prefix.h -Dmain=entry_main to build
# For multi-main ports: adds -include prefix.h to build, keeps objcopy --redefine-sym for main only

set -e
cd "$(dirname "$0")/.."

HELPER_INCLUDE='include("${CMAKE_CURRENT_LIST_DIR}/../../scripts/cmake/busyq_symbol_helpers.cmake")'

# ============================================================
# Helper function: convert a single-main autotools port
# Args: port_name prefix entry_point
# ============================================================
convert_single_autotools() {
    local port="$1" prefix="$2" entry="$3"
    local pf="ports/$port/portfile.cmake"
    echo "Converting $port (single-main autotools, prefix=$prefix, entry=$entry)..."

    # 1. Add helper include after alpine helpers
    if ! grep -q 'busyq_symbol_helpers' "$pf"; then
        sed -i '/busyq_alpine_helpers\.cmake")/a '"$HELPER_INCLUDE" "$pf"
    fi

    # 2. Add prefix header generation after include("${cmake_vars_file}")
    if ! grep -q "${prefix}_prefix.h" "$pf"; then
        sed -i '/include("${cmake_vars_file}")/a \
\
# --- Generate compile-time symbol prefix header (LTO-safe) ---\
set(_prefix_h "${SOURCE_PATH}/'"${prefix}"'_prefix.h")\
busyq_gen_prefix_header('"${prefix}"' "${_prefix_h}")' "$pf"
    fi

    # 3. Replace vcpkg_build_make() with version that includes prefix header + main rename
    sed -i 's|vcpkg_build_make()$|vcpkg_build_make(OPTIONS "CPPFLAGS=-include ${_prefix_h} -Dmain='"${entry}"'")|' "$pf"
    # Also handle vcpkg_build_make(BUILD_TARGET xxx)
    sed -i 's|vcpkg_build_make(BUILD_TARGET \([^ )]*\))|vcpkg_build_make(BUILD_TARGET \1 OPTIONS "CPPFLAGS=-include ${_prefix_h} -Dmain='"${entry}"'")|' "$pf"

    # 4. Replace the symbol isolation sh -c block (objcopy section)
    # Use python for multi-line replacement
    python3 - "$pf" "$prefix" <<'PYEOF'
import sys, re
pf, prefix = sys.argv[1], sys.argv[2]
with open(pf) as f:
    content = f.read()

# Find and replace the sh -c block that contains objcopy --prefix-symbols
# Pattern: vcpkg_execute_required_process(COMMAND sh -c "...objcopy --prefix-symbols...") block
pattern = re.compile(
    r'(# Steps?[ \d].*?\n)?'
    r'vcpkg_execute_required_process\(\s*\n'
    r'\s*COMMAND sh -c "\s*\n'
    r'(.*?objcopy --prefix-symbols.*?)'
    r'"\s*\n'
    r'\s*WORKING_DIRECTORY\s+"([^"]*)"\s*\n'
    r'\s*LOGNAME\s+"([^"]*)"\s*\n'
    r'\s*\)',
    re.DOTALL
)

# Extract output library name from the old block
lib_match = re.search(r"ar rcs '\$\{CURRENT_PACKAGES_DIR\}/lib/(lib\w+\.a)'", content)
lib_name = lib_match.group(1) if lib_match else f"lib{prefix}.a"

def replacement(m):
    wd = m.group(3)
    return f'''# Combine objects and package (no objcopy — compile-time prefix preserves bitcode)
vcpkg_execute_required_process(
    COMMAND sh -c "
        set -e
        ld -r --whole-archive lib_raw.a -o combined.o \\
            -z muldefs 2>/dev/null \\
        || ld -r --whole-archive lib_raw.a -o combined.o
        ar rcs '${{CURRENT_PACKAGES_DIR}}/lib/{lib_name}' combined.o
    "
    WORKING_DIRECTORY "{wd}"
    LOGNAME "combine-${{TARGET_TRIPLET}}"
)'''

new_content = pattern.sub(replacement, content)

# Also update raw archive name to lib_raw.a for consistency
# Find: ar rcs "${BUILD_REL}/lib*_raw.a" ${OBJS}
# The raw archive command may reference different names
new_content = re.sub(
    r'ar rcs "\$\{[^}]+\}/lib\w+_raw\.a"',
    lambda m: m.group().replace(m.group().split('/')[-1].rstrip('"'), 'lib_raw.a"'),
    new_content
)

if new_content != content:
    with open(pf, 'w') as f:
        f.write(new_content)
    print(f"  Replaced symbol isolation section")
else:
    print(f"  WARNING: Could not replace symbol isolation section")
PYEOF
}

# ============================================================
# Convert multi-main autotools ports
# Args: port_name prefix
# These keep objcopy --redefine-sym for main→entry rename but
# remove objcopy --prefix-symbols (the LTO-breaking operation)
# ============================================================
convert_multi_autotools() {
    local port="$1" prefix="$2"
    local pf="ports/$port/portfile.cmake"
    echo "Converting $port (multi-main autotools, prefix=$prefix)..."

    # 1. Add helper include
    if ! grep -q 'busyq_symbol_helpers' "$pf"; then
        sed -i '/busyq_alpine_helpers\.cmake")/a '"$HELPER_INCLUDE" "$pf"
    fi

    # 2. Add prefix header generation
    if ! grep -q "${prefix}_prefix.h" "$pf"; then
        sed -i '/include("${cmake_vars_file}")/a \
\
# --- Generate compile-time symbol prefix header (LTO-safe) ---\
set(_prefix_h "${SOURCE_PATH}/'"${prefix}"'_prefix.h")\
busyq_gen_prefix_header('"${prefix}"' "${_prefix_h}")' "$pf"
    fi

    # 3. Replace vcpkg_build_make() with version that includes prefix header only (no -Dmain)
    sed -i 's|vcpkg_build_make()$|vcpkg_build_make(OPTIONS "CPPFLAGS=-include ${_prefix_h}")|' "$pf"

    # 4. Remove objcopy --prefix-symbols and related unprefix logic, but keep --redefine-sym
    python3 - "$pf" "$prefix" <<'PYEOF'
import sys, re
pf, prefix = sys.argv[1], sys.argv[2]
with open(pf) as f:
    content = f.read()

# For multi-main ports, the symbol isolation script has this structure:
# 1. objcopy --redefine-sym main=xxx (per-tool main rename) — KEEP
# 2. ar rcs libxx_raw.a (rebuild after rename) — KEEP
# 3. ld -r --whole-archive ... (combine) — KEEP
# 4. nm -u ... (record undefined) — REMOVE
# 5. objcopy --prefix-symbols=xx_ ... — REMOVE (this is the LTO-breaking step)
# 6. sed redefine map generation — REMOVE
# 7. objcopy --redefine-syms=redefine.map — REMOVE
# 8. Entry point renames in redefine.map — need to convert to direct --redefine-sym
# 9. ar rcs final archive — KEEP

# Strategy: Replace the sh -c block that contains --prefix-symbols
# with a simplified version that only does ld -r + entry point renames + ar

pattern = re.compile(
    r'vcpkg_execute_required_process\(\s*\n'
    r'\s*COMMAND sh -c "\s*\n'
    r'(.*?objcopy --prefix-symbols.*?)'
    r'"\s*\n'
    r'\s*WORKING_DIRECTORY\s+"([^"]*)"\s*\n'
    r'\s*LOGNAME\s+"([^"]*)"\s*\n'
    r'\s*\)',
    re.DOTALL
)

match = pattern.search(content)
if not match:
    print(f"  WARNING: Could not find objcopy --prefix-symbols block in {pf}")
    sys.exit(0)

script_body = match.group(1)
wd = match.group(2)

# Extract the final ar rcs command to get the output library name
lib_match = re.search(r"ar rcs '(\$\{CURRENT_PACKAGES_DIR\}/lib/lib\w+\.a)'", script_body)
lib_path = lib_match.group(1) if lib_match else f"${{CURRENT_PACKAGES_DIR}}/lib/lib{prefix}.a"

# Extract entry point renames from the echo lines
# Pattern: echo 'PREFIX_xxx_main_orig yyy_main' >> redefine.map
entry_renames = re.findall(r"echo '(\w+) (\w+)' >> redefine\.map", script_body)
# Filter to only the actual entry point renames (not the unprefix ones)
entry_renames = [(old, new) for old, new in entry_renames
                 if '_main' in new and not old.startswith(prefix + '_')]

# Also look for dynamic renames (nm ... | while read ... pattern in procps/psmisc)
has_dynamic_rename = 'while read' in script_body or 'while IFS' in script_body

# Extract the raw archive name used in ld -r
raw_archive_match = re.search(r'ld -r --whole-archive (\w+\.a)', script_body)
raw_archive = raw_archive_match.group(1) if raw_archive_match else 'lib_raw.a'

# Also check for find ... | xargs ar rcs pattern (rebuild with renamed mains)
has_rebuild = 'xargs ar rcs' in script_body or 'find ' in script_body

# Build the new simplified script
new_lines = ['        set -e', '']

# If there's a rebuild step (find ... | xargs ar rcs), include it
if has_rebuild:
    # Extract the find+ar command
    find_match = re.search(r'(find .*? \| xargs ar rcs \w+\.a)', script_body)
    if find_match:
        new_lines.append(f'        # Rebuild archive with renamed mains')
        new_lines.append(f'        {find_match.group(1)}')
        new_lines.append('')

# Also check for obj_list.txt pattern (used by procps/psmisc)
if 'obj_list.txt' in script_body:
    obj_list_match = re.search(r'(find .*?> obj_list\.txt)', script_body)
    ar_obj_match = re.search(r'(ar rcs \w+\.a .*?obj_list.*)', script_body)
    if obj_list_match:
        new_lines.append(f'        {obj_list_match.group(1)}')
    if ar_obj_match:
        new_lines.append(f'        {ar_obj_match.group(1)}')
    new_lines.append('')

# ld -r step
new_lines.append(f'        # Combine all objects into one relocatable .o')
new_lines.append(f'        ld -r --whole-archive {raw_archive} -o combined.o \\')
new_lines.append(f'            -z muldefs 2>/dev/null \\')
new_lines.append(f'        || ld -r --whole-archive {raw_archive} -o combined.o')
new_lines.append('')

# Entry point renames using objcopy --redefine-sym (safe for single symbol)
# The mains were already renamed to xxx_main_orig in the pre-step.
# After ld -r combine (without prefix-symbols), the names are just xxx_main_orig.
# We need to rename them to the final entry points.
if entry_renames:
    new_lines.append(f'        # Rename entry points')
    for old_name, new_name in entry_renames:
        # The old name no longer has the prefix_ prefix since we're not using
        # objcopy --prefix-symbols. The original rename was main→xxx_main_orig.
        # So the symbol in the combined.o is xxx_main_orig (no prefix_ prefix).
        # Extract the original pre-prefix name
        orig_name = old_name
        if old_name.startswith(prefix + '_'):
            orig_name = old_name[len(prefix) + 1:]
        new_lines.append(f"        objcopy --redefine-sym {orig_name}={new_name} combined.o")

if has_dynamic_rename:
    new_lines.append(f'        # Rename entry points (dynamic — based on object file basenames)')
    new_lines.append(f"        nm combined.o 2>/dev/null | grep '_main_orig' | sed 's/.* //' | while read sym; do")
    new_lines.append(f"            tool=$(echo \"$sym\" | sed 's/_main_orig$//')")
    new_lines.append(f"            objcopy --redefine-sym \"$sym\" \"${{tool}}_main\" combined.o")
    new_lines.append(f"        done")

new_lines.append('')
new_lines.append(f"        # Package into final archive")
new_lines.append(f"        ar rcs '{lib_path}' combined.o")

new_script = '\n'.join(new_lines)

replacement = f'''# Combine objects and rename entry points (no --prefix-symbols — preserves bitcode)
vcpkg_execute_required_process(
    COMMAND sh -c "
{new_script}
    "
    WORKING_DIRECTORY "{wd}"
    LOGNAME "combine-${{TARGET_TRIPLET}}"
)'''

new_content = content[:match.start()] + replacement + content[match.end():]

# Also update the raw archive reference in the earlier ar step
# Standardize raw archive names to lib_raw.a
# Actually, leave raw archive names as-is since the pre-steps reference them

with open(pf, 'w') as f:
    f.write(new_content)
print(f"  Replaced symbol isolation section")
PYEOF
}

# ============================================================
# Process all single-main autotools ports
# ============================================================
convert_single_autotools busyq-gawk gawk gawk_main
convert_single_autotools busyq-sed sed sed_main
convert_single_autotools busyq-grep grep grep_main
convert_single_autotools busyq-patch patch patch_main
convert_single_autotools busyq-tar tar tar_main
convert_single_autotools busyq-gzip gz gzip_main
convert_single_autotools busyq-xz xz xz_main
convert_single_autotools busyq-cpio cpio cpio_main
convert_single_autotools busyq-lzop lzop lzop_main
convert_single_autotools busyq-less less less_main
convert_single_autotools busyq-time time time_main
convert_single_autotools busyq-which which which_main
convert_single_autotools busyq-wget wget wget_main
convert_single_autotools busyq-lsof lsof lsof_main

# ============================================================
# Process multi-main autotools ports
# ============================================================
convert_multi_autotools busyq-bc bc
convert_multi_autotools busyq-diffutils diff
convert_multi_autotools busyq-findutils fu
convert_multi_autotools busyq-sharutils shar
convert_multi_autotools busyq-procps procps
convert_multi_autotools busyq-psmisc psmisc

echo ""
echo "Done converting autotools ports."
echo ""
echo "Manual ports (bzip2, dos2unix, ed, zip) need individual handling."
