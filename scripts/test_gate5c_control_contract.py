#!/usr/bin/env python3
"""Pinned-source control coverage and integration regression checks, not device QA."""
import json,re
from pathlib import Path
r=Path(__file__).resolve().parents[1]
spec=json.loads((r/'config/engine/ios_source_patches.json').read_text())
menu='\n'.join(x['new'] for p in spec['patches'] if p['path']=='menu.c' for x in p['replacements'])
assert 'WrathIOSGate5CSetMenuActive(1)' not in menu, 'in-game menu draw must not reset gameplay mode'
assert 'MP_InputEvent(0, K_MOUSE1, 0)' in menu
assert 'MP_KeyEvent(K_MOUSE1' not in menu, 'pinned QC legacy callbacks are empty'
for field in ('menu_createprofile','menu_current','ui_selected','uielement_c::__mpartner'):
    assert '"'+field+'"' in menu
assert 'WrathIOSTouchNextText()' in menu
assert 'MP_InputEvent(0, K_X360_A, 0)' in menu
assert 'MP_InputEvent(6, 2, x)' in menu and 'MP_InputEvent(6, 3, y)' in menu
source=(r/'Vendor/wrath-qc/menuqc/menu.qc').read_text()
section=source.split('keybind_t controllerdiagram_validcontrols[] = {',1)[1].split('};',1)[0]
required=set(re.findall(r'\), "([^"]+)", 0',section))
assert len(required)>=30
header=(r/'Gate5C/WrathTouchActions.hpp').read_text()
covered={'+forward','+back','+moveleft','+moveright','togglemenu'} # stick axes and native Escape
for label,rawdown,rawup in re.findall(r'\{"([^"\\]*)","((?:\\.|[^"\\])*)","((?:\\.|[^"\\])*)"\}',header):
    down=json.loads('"'+rawdown+'"').strip();up=json.loads('"'+rawup+'"').strip()
    if down.startswith('+'):
        covered.add(down.split()[0]);assert up[1:]==down[1:] and up.startswith('-')
    elif down:covered.add(down)
assert not required-covered, 'unreachable game controls: '+str(required-covered)
print(f'Control contract passed: {len(required)} actual WRATH bindings covered; real menu handler, gameplay mode and profile keyboard hooks verified')

pack=(r/"scripts/build_gate5c_device_semantic_menu.sh").read_text()
assert '"$build_version" == "$expected_build_version"' in pack
assert '"$short_version" == "$expected_short_version"' in pack
