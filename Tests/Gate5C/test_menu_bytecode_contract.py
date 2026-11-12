"""Validate target compatibility and actual exported VM symbols, not string matches."""
from pathlib import Path
import struct
root = Path(__file__).resolve().parents[2]
b = (root / 'Gate5C/Resources/wrathios-menu.dat').read_bytes()
h = struct.unpack_from('<15i', b)
assert h[0] == 6, 'WRATH requires standard version-6 program layout'
assert h[2] + h[3] * 8 <= len(b)
ops = {struct.unpack_from('<H', b, h[2] + i * 8)[0] for i in range(h[3])}
assert max(ops) <= 65, 'WRATH fork disables extended FTE/DP opcodes'
strings = b[h[10]:h[10] + h[11]]
def definitions(offset, count):
    out = {}
    for i in range(count):
        typ, address, name = struct.unpack_from('<HHI', b, offset + i * 8)
        name = strings[name:].split(b'\0', 1)[0].decode()
        out[name] = (typ & 32767, address)
    return out
globals_ = definitions(h[4], h[5]); fields = definitions(h[6], h[7])
for name in ('menu_current', 'menu_createprofile', 'ui_selected'):
    assert globals_[name][0] == 4, name
assert globals_['input_mode'][0] == 2
assert fields['uielement_c::__mpartner'][0] == 4
functions = {}
for i in range(h[9]):
    f = struct.unpack_from('<7i8B', b, h[8] + i * 36)
    name = strings[f[4]:].split(b'\0', 1)[0].decode()
    functions[name] = f[0]
assert functions['Menu_InputEvent'] > 0
print('Menu bytecode: v6/opcodes0..65, entity globals, mangled partner field and real input handler passed')
