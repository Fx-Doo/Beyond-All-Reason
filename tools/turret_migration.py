#!/usr/bin/env python3
"""
BAR Turret Speed Migration Tool
Extracts hardcoded turn speeds from AimWeaponN BOS functions,
patches BOS files to use unitDefsTurretSpeeds.h static-vars,
and injects matching customparams into unitDef Lua files.

Usage:  python turret_migration.py [--dry-run] [--unit UNITNAME]
Output: tools/migration_output/
          report.txt           – per-unit summary of changes
          turret_speeds.json   – extracted data
          bos_patched/         – modified BOS files (staging)
          unitdefs_patched/    – modified unitDef Lua files (staging)

Apply staging:
  After review, run:  python turret_migration.py --apply
"""

import os, re, json, shutil, argparse, sys
from pathlib import Path
from collections import defaultdict

# ─── Paths ────────────────────────────────────────────────────────────────────
GAME_DIR    = Path(r"C:\Program Files\Beyond-All-Reason\data\games\BAR.sdd")
SCRIPTS_DIR = GAME_DIR / "scripts" / "Units"
UNITS_DIR   = GAME_DIR / "units"
OUTPUT_DIR  = GAME_DIR / "tools" / "migration_output"
BOS_OUT     = OUTPUT_DIR / "bos_patched"
UDEF_OUT    = OUTPUT_DIR / "unitdefs_patched"
HEADER_LINE = '#include "../unitDefsTurretSpeeds.h"'

# ─── BOS parsing ──────────────────────────────────────────────────────────────

def extract_function_body(text, start_search):
    """Starting at start_search, find the next '{...}' block (brace-balanced).
    Returns (body_start, body_end) indices into text, or None."""
    pos = start_search
    while pos < len(text) and text[pos] != '{':
        if text[pos] == ';':   # hit a statement before any brace – not a function
            return None
        pos += 1
    if pos >= len(text):
        return None
    depth = 0
    for i in range(pos, len(text)):
        if text[i] == '{':
            depth += 1
        elif text[i] == '}':
            depth -= 1
            if depth == 0:
                return pos, i + 1
    return None


def extract_aim_speeds(bos_text):
    """Return dict { wpn_num: { 'y': float|None, 'x': float|None, 'pieces_y': list, 'pieces_x': list } }"""
    speeds = {}
    for wpn_num in range(1, 11):
        pat = re.compile(rf'\bAimWeapon{wpn_num}\s*\(', re.IGNORECASE)
        m = pat.search(bos_text)
        if not m:
            continue
        body_range = extract_function_body(bos_text, m.end())
        if not body_range:
            continue
        body = bos_text[body_range[0]:body_range[1]]

        wpn = {'y': None, 'x': None, 'pieces_y': [], 'pieces_x': [],
               'complex': False, 'complex_reason': '', 'already_migrated': False}

        # Detect already-migrated: speed uses WeaponNTurretY/X variable
        already_re = re.compile(
            rf'\bturn\s+\w+\s+to\s+([xy])-axis\s+[^;]+?speed\s+Weapon{wpn_num}Turret([XY])\b',
            re.DOTALL | re.IGNORECASE
        )
        if already_re.search(body):
            wpn['already_migrated'] = True
            # Extract default values from static-var initializations in the full script
            for axis_char, axis_key in [('Y', 'y'), ('X', 'x')]:
                init_m = re.search(
                    rf'\bWeapon{wpn_num}Turret{axis_char}\s*=\s*<([\d.]+)>',
                    bos_text, re.IGNORECASE
                )
                if init_m:
                    wpn[axis_key] = float(init_m.group(1))
            wpn['body_start'] = body_range[0]
            wpn['body_end']   = body_range[1]
            speeds[wpn_num] = wpn
            continue

        # Improved extraction: split into TWO passes
        # Pass 1: turns where GOAL explicitly uses 'heading' (y-axis) or 'pitch' (x-axis)
        #          → these are the MAIN aim turns
        # Pass 2: any other literal-speed turns → secondary / cosmetic
        aim_turn_re = re.compile(
            r'\bturn\s+(\w+)\s+to\s+([xy])-axis\s+([^;]+?)speed\s+<([\d.]+)>',
            re.DOTALL | re.IGNORECASE
        )
        main_y = None   # speed of turn with 'heading' in goal (not scaled)
        main_x = None   # speed of turn with 'pitch' in goal  (not scaled)
        any_y  = None   # first literal y-axis speed (fallback)
        any_x  = None   # first literal x-axis speed (fallback)
        conflicting_y = False
        conflicting_x = False

        # "Main aim" = goal uses the param variable directly, not scaled (/ or *)
        # e.g. "heading" yes, "0 - pitch" yes, "pitch / 2" NO, "heading + offset" edge-case → yes
        def is_main_aim(goal, param):
            g = goal.lower().strip()
            if param not in g:
                return False
            # Reject if the param appears only in a fraction/product (e.g. pitch/2, pitch*3)
            # Find the param and check the character immediately after it (ignoring spaces)
            for m2 in re.finditer(re.escape(param), g):
                after = g[m2.end():].lstrip()
                if after and after[0] in ('/', '*'):
                    continue   # this occurrence is scaled
                return True    # found an unscaled occurrence
            return False

        for tm in aim_turn_re.finditer(body):
            piece, axis, goal, val = tm.group(1), tm.group(2), tm.group(3), float(tm.group(4))
            is_main = is_main_aim(goal, 'heading' if axis == 'y' else 'pitch')
            if axis == 'y':
                if is_main:
                    if main_y is None:  main_y = val
                    elif main_y != val: conflicting_y = True
                if any_y is None: any_y = val
                wpn['pieces_y'].append(piece)
            else:
                if is_main:
                    if main_x is None:  main_x = val
                    elif main_x != val: conflicting_x = True
                if any_x is None: any_x = val
                wpn['pieces_x'].append(piece)

        # Prefer main aim speed, fall back to first any speed
        wpn['y'] = main_y if main_y is not None else any_y
        wpn['x'] = main_x if main_x is not None else any_x

        reasons = []
        if conflicting_y: reasons.append('conflicting y-speeds')
        if conflicting_x: reasons.append('conflicting x-speeds')

        # Flag if remaining variable-speed turns exist (not already-migrated ones)
        var_speed_re = re.compile(
            r'\bturn\s+\w+\s+to\s+[xy]-axis\s+[^;]+?speed\s+(?!<)(\w+)', re.DOTALL | re.IGNORECASE
        )
        for vsm in var_speed_re.finditer(body):
            var_name = vsm.group(1)
            # Skip loop variables and known-safe identifiers
            if var_name.lower() not in ('animspeed', 'movespeed') and \
               not re.match(rf'weapon\d+turret[xy]', var_name, re.IGNORECASE):
                reasons.append(f'variable speed: {var_name}')

        if reasons:
            wpn['complex'] = True
            wpn['complex_reason'] = '; '.join(reasons)

        if wpn['y'] is not None or wpn['x'] is not None:
            wpn['body_start'] = body_range[0]
            wpn['body_end']   = body_range[1]
            speeds[wpn_num] = wpn

    return speeds


# ─── BOS patching ─────────────────────────────────────────────────────────────

def insert_after_first_include(text):
    """Insert unitDefsTurretSpeeds.h include after the first #include line."""
    if 'unitDefsTurretSpeeds' in text:
        return text, False  # already present
    m = re.search(r'^#include\s+"[^"]+"[^\n]*$', text, re.MULTILINE)
    if not m:
        # No existing include – insert at very top
        return HEADER_LINE + '\n\n' + text, True
    pos = m.end()
    return text[:pos] + '\n' + HEADER_LINE + text[pos:], True


def add_defaults_to_create(text, speeds):
    """Insert default Weapon{N}TurretY/X = <VAL>; lines at the start of Create() body."""
    m = re.search(r'^\s*Create\s*\(\s*\)', text, re.MULTILINE)
    if not m:
        return text, False
    body_range = extract_function_body(text, m.end())
    if not body_range:
        return text, False
    bstart, bend = body_range
    # Build lines to insert (only for weapons we extracted)
    inserts = []
    for wpn_num in sorted(speeds.keys()):
        ws = speeds[wpn_num]
        if ws.get('complex'):
            continue
        if ws['y'] is not None:
            inserts.append(f'\tWeapon{wpn_num}TurretY = <{ws["y"]}>;  // default – overridden by gadget')
        if ws['x'] is not None:
            inserts.append(f'\tWeapon{wpn_num}TurretX = <{ws["x"]}>;  // default – overridden by gadget')
    if not inserts:
        return text, False
    insert_str = '\n'.join(inserts) + '\n'
    # Insert just after opening brace of Create()
    new_text = text[:bstart + 1] + '\n' + insert_str + text[bstart + 1:]
    return new_text, True


def replace_speeds_in_aim_functions(text, speeds):
    """Replace literal speed <VAL> with Weapon{N}TurretY/X inside each AimWeaponN body."""
    # We need to work on ranges, but text has been modified by previous steps.
    # Re-locate each AimWeaponN function and patch within its body.
    changed = False
    for wpn_num in sorted(speeds.keys()):
        ws = speeds[wpn_num]
        if ws.get('complex'):
            continue
        pat = re.compile(rf'\bAimWeapon{wpn_num}\s*\(', re.IGNORECASE)
        m = pat.search(text)
        if not m:
            continue
        body_range = extract_function_body(text, m.end())
        if not body_range:
            continue
        bstart, bend = body_range
        body = text[bstart:bend]
        new_body = body

        if ws['y'] is not None:
            # Replace   speed <450.0>   →   speed Weapon1TurretY
            # Only when on a y-axis turn line
            y_re = re.compile(
                r'(turn\s+\w+\s+to\s+y-axis\s+[^;]+?speed\s+)<([\d.]+)>',
                re.DOTALL | re.IGNORECASE
            )
            new_body = y_re.sub(rf'\g<1>Weapon{wpn_num}TurretY', new_body)
        if ws['x'] is not None:
            x_re = re.compile(
                r'(turn\s+\w+\s+to\s+x-axis\s+[^;]+?speed\s+)<([\d.]+)>',
                re.DOTALL | re.IGNORECASE
            )
            new_body = x_re.sub(rf'\g<1>Weapon{wpn_num}TurretX', new_body)

        if new_body != body:
            text = text[:bstart] + new_body + text[bend:]
            changed = True

    return text, changed


def patch_bos(bos_text, speeds):
    """Apply all BOS patches. Returns (new_text, changes_dict)."""
    text = bos_text
    changes = {}

    text, c1 = insert_after_first_include(text)
    changes['include_added'] = c1

    text, c2 = add_defaults_to_create(text, speeds)
    changes['defaults_added'] = c2

    text, c3 = replace_speeds_in_aim_functions(text, speeds)
    changes['speeds_replaced'] = c3

    return text, changes


# ─── unitDef patching ─────────────────────────────────────────────────────────

def find_unitdefs_for_script(script_stem, all_udef_files):
    """Return list of unitDef files that reference script_stem.cob (case-insensitive)."""
    pattern = re.compile(
        rf'script\s*=\s*"[Uu]nits/{re.escape(script_stem)}\.cob"',
        re.IGNORECASE
    )
    matches = []
    for path in all_udef_files:
        try:
            content = path.read_text(encoding='utf-8', errors='replace')
            if pattern.search(content):
                matches.append(path)
        except Exception:
            pass
    return matches


def build_customparams_snippet(speeds):
    """Return list of 'key = "val"' strings to inject into customparams."""
    lines = []
    for wpn_num in sorted(speeds.keys()):
        ws = speeds[wpn_num]
        if ws.get('complex'):
            continue
        if ws['y'] is not None:
            lines.append(f'\t\t\twpn{wpn_num}turrety = "{int(round(ws["y"]))}",')
        if ws['x'] is not None:
            lines.append(f'\t\t\twpn{wpn_num}turretx = "{int(round(ws["x"]))}",') 
    return lines


def patch_unitdef(udef_text, cp_lines):
    """Insert customparams lines into existing customparams = { ... } block.
    If no customparams block exists, note the issue. Returns (new_text, ok)."""
    if not cp_lines:
        return udef_text, False

    # Find existing customparams = { block
    cp_m = re.search(r'\bcustomparams\s*=\s*\{', udef_text, re.IGNORECASE)
    if cp_m:
        body_range = extract_function_body(udef_text, cp_m.end() - 1)  # start at the '{'
        if body_range:
            bstart, bend = body_range
            # Check if keys already present
            insert_lines = []
            for line in cp_lines:
                key = line.strip().split('=')[0].strip()
                if key not in udef_text[bstart:bend]:
                    insert_lines.append(line)
            if not insert_lines:
                return udef_text, False
            # Insert before closing brace
            insert_str = '\n' + '\n'.join(insert_lines)
            new_text = udef_text[:bend - 1] + insert_str + '\n\t\t' + udef_text[bend - 1:]
            return new_text, True
    # No customparams block – this is unusual, flag it
    return udef_text, False


# ─── LUS script handling ──────────────────────────────────────────────────────

LUS_DIR = GAME_DIR / "scripts" / "Units"
LUS_OUT = OUTPUT_DIR / "lus_patched"

def extract_lus_aim_speeds(lus_text):
    """Extract turn speeds from Spring Lua unit scripts.
    Turn() in LUS: Turn(piece, axis, angle, speed) where speed is rad/sec.
    We find turns in AimWeapon functions and convert back to deg/sec for customParams.
    Returns same format as extract_aim_speeds.
    """
    import math
    speeds = {}
    # AimWeapon function pattern in Lua
    for wpn_num in range(1, 11):
        # Lua: function script.AimWeapon1(heading, pitch) or local function AimWeapon1(...)
        pat = re.compile(rf'\bAimWeapon{wpn_num}\s*\(', re.IGNORECASE)
        m = pat.search(lus_text)
        if not m:
            continue
        # Find function body – Lua uses 'end' not braces, scan for balanced end
        body = extract_lua_function_body(lus_text, m.start())
        if not body:
            continue

        wpn = {'y': None, 'x': None, 'complex': False, 'already_migrated': False,
               'complex_reason': '', 'pieces_y': [], 'pieces_x': []}

        # Turn(piece, axis, angle, speed)  axis: 1=x, 2=y  (Spring Lua constants)
        # rad() converts degrees to radians; speed is rad/sec
        # Pattern: Turn(piece, 2, ..., rad(SPEED))  → y-axis heading
        #          Turn(piece, 1, ..., rad(SPEED))  → x-axis pitch
        turn_re = re.compile(
            r'\bTurn\s*\(\s*(\w+)\s*,\s*([12])\s*,[^,]+,\s*rad\s*\(\s*([\d.]+)\s*\)',
            re.IGNORECASE
        )
        for tm in turn_re.finditer(body):
            piece, axis_num, val_deg = tm.group(1), tm.group(2), float(tm.group(3))
            axis = 'y' if axis_num == '2' else 'x'
            if axis == 'y':
                if wpn['y'] is None: wpn['y'] = val_deg
                elif wpn['y'] != val_deg: wpn['complex'] = True
                wpn['pieces_y'].append(piece)
            else:
                if wpn['x'] is None: wpn['x'] = val_deg
                elif wpn['x'] != val_deg: wpn['complex'] = True
                wpn['pieces_x'].append(piece)

        if wpn['y'] is not None or wpn['x'] is not None:
            speeds[wpn_num] = wpn
    return speeds


def extract_lua_function_body(lus_text, func_start):
    """Extract Lua function body (between 'function' keyword and matching 'end').
    Returns body string or None."""
    # Find 'function' keyword before or at func_start
    # Actually we just need to find balanced end after the function signature
    # Find the line with the function and scan for 'end'
    depth = 0
    pos = func_start
    # Find opening – scan for 'function' or 'if'/'for'/'while' to track nesting
    keywords_open  = re.compile(r'\b(function|if|for|while|do|repeat)\b')
    keywords_close = re.compile(r'\bend\b')
    # We need to first find the function keyword
    fn_m = re.compile(r'\bfunction\b').search(lus_text, pos)
    if not fn_m:
        return None
    scan_start = fn_m.end()
    # Simple scan: count function/if/for/while/do/repeat as +1, end as -1
    body_start = scan_start
    depth = 1
    i = scan_start
    while i < len(lus_text) and depth > 0:
        mo = keywords_open.search(lus_text, i)
        mc = keywords_close.search(lus_text, i)
        if mc is None:
            break
        if mo is not None and mo.start() < mc.start():
            depth += 1
            i = mo.end()
        else:
            depth -= 1
            i = mc.end()
    if depth == 0:
        return lus_text[body_start:i]
    return None


def patch_lus_file(lus_text, script_name, speeds):
    """Patch LUS script to read turret speeds from customParams.
    Inserts at the start of each AimWeaponN function a local var that reads from customParams,
    and replaces the hardcoded rad(X) speed with the variable.
    """
    text = lus_text
    changed = False
    for wpn_num, ws in sorted(speeds.items()):
        if ws.get('complex') or ws.get('already_migrated'):
            continue
        # Build replacement: add local vars and replace Turn calls
        pat = re.compile(rf'\bAimWeapon{wpn_num}\s*\(', re.IGNORECASE)
        m = pat.search(text)
        if not m:
            continue
        fn_m = re.compile(r'\bfunction\b').search(text, m.start())
        if not fn_m:
            continue
        body = extract_lua_function_body(text, m.start())
        if not body:
            continue
        body_start = fn_m.end()
        body_text = text[body_start:body_start + len(body)]

        new_body = body_text
        # Add local speed vars after function header line
        first_nl = new_body.find('\n')
        inserts = []
        if ws['y'] is not None:
            inserts.append(f'\tlocal wpn{wpn_num}turretY = rad(tonumber((Spring.GetUnitDefID and UnitDefs[unitDefID] or {{customParams={{}}}}).customParams.wpn{wpn_num}turrety) or {ws["y"]})')
        if ws['x'] is not None:
            inserts.append(f'\tlocal wpn{wpn_num}turretX = rad(tonumber((Spring.GetUnitDefID and UnitDefs[unitDefID] or {{customParams={{}}}}).customParams.wpn{wpn_num}turretx) or {ws["x"]})')

        if inserts:
            new_body = new_body[:first_nl + 1] + '\n'.join(inserts) + '\n' + new_body[first_nl + 1:]

        # Replace Turn(piece, 2, ..., rad(Y)) with Turn(piece, 2, ..., wpn1turretY)
        if ws['y'] is not None:
            new_body = re.sub(
                rf'(Turn\s*\(\s*\w+\s*,\s*2\s*,[^,]+,\s*)rad\s*\(\s*{re.escape(str(ws["y"]))}\s*\)',
                rf'\g<1>wpn{wpn_num}turretY', new_body
            )
        if ws['x'] is not None:
            new_body = re.sub(
                rf'(Turn\s*\(\s*\w+\s*,\s*1\s*,[^,]+,\s*)rad\s*\(\s*{re.escape(str(ws["x"]))}\s*\)',
                rf'\g<1>wpn{wpn_num}turretX', new_body
            )

        if new_body != body_text:
            text = text[:body_start] + new_body + text[body_start + len(body_text):]
            changed = True

    return text, changed


def process_lus_scripts(all_udef_files, dry_run=False):
    """Process all active LUS scripts."""
    LUS_OUT.mkdir(parents=True, exist_ok=True)
    lus_files = [f for f in LUS_DIR.glob('*.lua')
                 if not f.name.endswith('_old')]
    print(f'Processing {len(lus_files)} LUS scripts...')
    lus_data = {}
    for lus_path in sorted(lus_files):
        stem = lus_path.stem
        text = lus_path.read_text(encoding='utf-8', errors='replace')
        speeds = extract_lus_aim_speeds(text)
        if not speeds:
            continue
        lus_data[stem] = speeds
        print(f'  {stem}: {speeds}')
        if dry_run:
            continue
        # Patch LUS
        new_text, changed = patch_lus_file(text, stem, speeds)
        if changed:
            (LUS_OUT / lus_path.name).write_text(new_text, encoding='utf-8')
        # Patch unitDefs (same as BOS path)
        cp_lines = build_customparams_snippet(speeds)
        if cp_lines:
            # LUS script name for unitDef lookup (e.g. armcom_lus → armcom)
            lookup_stem = re.sub(r'_lus$', '', stem, flags=re.IGNORECASE)
            udef_paths = find_unitdefs_for_script(lookup_stem, all_udef_files)
            if not udef_paths:
                udef_paths = find_unitdefs_for_script(stem, all_udef_files)
            for udef_path in udef_paths:
                udef_text = udef_path.read_text(encoding='utf-8', errors='replace')
                new_udef, ok = patch_unitdef(udef_text, cp_lines)
                if ok:
                    rel = udef_path.relative_to(UNITS_DIR)
                    out_udef = UDEF_OUT / rel
                    out_udef.parent.mkdir(parents=True, exist_ok=True)
                    out_udef.write_text(new_udef, encoding='utf-8')
    return lus_data


# ─── Main ─────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description='BAR turret speed migration')
    parser.add_argument('--dry-run', action='store_true',
                        help='Extract and report only, write nothing')
    parser.add_argument('--unit', default=None,
                        help='Process only this unit (e.g. armflea)')
    parser.add_argument('--apply', action='store_true',
                        help='Copy staged files over originals (after review)')
    args = parser.parse_args()

    if args.apply:
        apply_staged()
        return

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    BOS_OUT.mkdir(parents=True, exist_ok=True)
    UDEF_OUT.mkdir(parents=True, exist_ok=True)

    # Collect all unitDef files once
    all_udef_files = list(UNITS_DIR.rglob('*.lua'))
    print(f'Found {len(all_udef_files)} unitDef files')

    # Collect BOS files
    bos_files = sorted(SCRIPTS_DIR.glob('*.bos'))
    if args.unit:
        bos_files = [f for f in bos_files if f.stem.lower() == args.unit.lower()]
    print(f'Processing {len(bos_files)} BOS files...')

    all_data = {}   # script_stem → speeds dict
    report_lines = []
    skipped = []
    already_migrated_units = []
    complex_units = []

    for bos_path in bos_files:
        stem = bos_path.stem.lower()
        try:
            text = bos_path.read_text(encoding='utf-8', errors='replace')
        except Exception as e:
            skipped.append(f'{stem}: read error – {e}')
            continue

        speeds = extract_aim_speeds(text)
        if not speeds:
            continue

        # Check for complex / already-migrated cases
        has_complex = any(s.get('complex') for s in speeds.values())
        has_already  = any(s.get('already_migrated') for s in speeds.values())
        all_data[stem] = speeds

        # Build report entry
        line = f'{stem}:'
        for wpn_num, ws in sorted(speeds.items()):
            if ws.get('already_migrated'):
                flag = ' [ALREADY-MIGRATED]'
            elif ws.get('complex'):
                flag = f' [COMPLEX: {ws.get("complex_reason","?")}]'
            else:
                flag = ''
            y = f'{ws["y"]:.1f}' if ws["y"] else '-'
            x = f'{ws["x"]:.1f}' if ws["x"] else '-'
            line += f'  wpn{wpn_num}(y={y}, x={x}){flag}'
        report_lines.append(line)
        if has_complex:   complex_units.append(stem)
        if has_already:   already_migrated_units.append(stem)

        if args.dry_run:
            continue

        # Patch BOS (skip already-migrated, patch complex if values were extracted)
        needs_bos_patch = not all(s.get('already_migrated') for s in speeds.values())
        if needs_bos_patch:
            new_text, changes = patch_bos(text, speeds)
            if new_text != text:
                out_path = BOS_OUT / bos_path.name
                out_path.write_text(new_text, encoding='utf-8')

        # Find and patch unitDefs
        cp_lines = build_customparams_snippet(speeds)
        if cp_lines:
            udef_paths = find_unitdefs_for_script(bos_path.stem, all_udef_files)
            for udef_path in udef_paths:
                udef_text = udef_path.read_text(encoding='utf-8', errors='replace')
                new_udef, ok = patch_unitdef(udef_text, cp_lines)
                if ok:
                    # Mirror directory structure under UDEF_OUT
                    rel = udef_path.relative_to(UNITS_DIR)
                    out_udef = UDEF_OUT / rel
                    out_udef.parent.mkdir(parents=True, exist_ok=True)
                    out_udef.write_text(new_udef, encoding='utf-8')

    # Write outputs
    (OUTPUT_DIR / 'turret_speeds.json').write_text(
        json.dumps(
            {k: {str(n): {'y': v['y'], 'x': v['x'], 'complex': v.get('complex', False)}
                 for n, v in speeds.items()}
             for k, speeds in all_data.items()},
            indent=2
        ),
        encoding='utf-8'
    )

    report = '\n'.join(report_lines)
    if already_migrated_units:
        report += '\n\n--- ALREADY MIGRATED (BOS unchanged, customParams only) ---\n'
        report += '\n'.join(already_migrated_units)
    if complex_units:
        report += '\n\n--- STILL COMPLEX (manual review) ---\n'
        report += '\n'.join(complex_units)
    if skipped:
        report += '\n\n--- SKIPPED ---\n' + '\n'.join(skipped)
    (OUTPUT_DIR / 'report.txt').write_text(report, encoding='utf-8')

    print(f'\nDone. {len(all_data)} units with turret speeds.')
    print(f'Already migrated (customParams only): {len(already_migrated_units)}')
    print(f'Complex (manual review): {len(complex_units)}')
    print(f'Report: {OUTPUT_DIR / "report.txt"}')
    if not args.dry_run:
        bos_count  = len(list(BOS_OUT.glob('*.bos')))
        udef_count = len(list(UDEF_OUT.rglob('*.lua')))
        lus_count  = len(list(LUS_OUT.glob('*.lua'))) if LUS_OUT.exists() else 0
        print(f'Staged:  {bos_count} BOS, {udef_count} unitDef, {lus_count} LUS files')
        print(f'Review staging dir, then run:  python turret_migration.py --apply')

    # ── LUS scripts ──────────────────────────────────────────────────────────
    if not args.unit:   # LUS always processed unless scoped to one BOS unit
        process_lus_scripts(all_udef_files, dry_run=args.dry_run)


def apply_staged():
    """Copy staged BOS, LUS and unitDef files over originals."""
    bos_files = list(BOS_OUT.glob('*.bos'))
    for src in bos_files:
        dst = SCRIPTS_DIR / src.name
        shutil.copy2(src, dst)
        print(f'  BOS applied: {dst.name}')

    lus_files = list(LUS_OUT.glob('*.lua')) if LUS_OUT.exists() else []
    for src in lus_files:
        dst = SCRIPTS_DIR / src.name
        shutil.copy2(src, dst)
        print(f'  LUS applied: {dst.name}')

    udef_files = list(UDEF_OUT.rglob('*.lua'))
    for src in udef_files:
        rel = src.relative_to(UDEF_OUT)
        dst = UNITS_DIR / rel
        shutil.copy2(src, dst)
        print(f'  UDef applied: {rel}')

    print(f'Applied {len(bos_files)} BOS + {len(lus_files)} LUS + {len(udef_files)} unitDef files.')


if __name__ == '__main__':
    main()
