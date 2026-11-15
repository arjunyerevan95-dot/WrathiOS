#!/usr/bin/env python3
"""Use the pinned engine's actual FXAA kernel in the bounded GPU smoke test."""
import ast
import hashlib
import json
from pathlib import Path

root=Path(__file__).resolve().parents[1]
lines=(root/'Vendor/wrath-darkplaces/shader_glsl.h').read_text(encoding='utf-8').splitlines()
start=next(i for i,l in enumerate(lines) if l.startswith('"vec4 fxaa('))
kernel=[];depth=0
for line in lines[start:]:
    text=ast.literal_eval(line.rstrip().removesuffix(','));kernel.append(text)
    depth+=text.count('{')-text.count('}')
    if len(kernel)>2 and depth==0:break
kernel=''.join(kernel)
prefix='precision highp float;varying highp vec2 TexCoord1;uniform sampler2D Texture_First;uniform vec2 PixelSize;\n#define dp_texture2D texture2D\n'
fragment=prefix+kernel+'\nvoid main(){gl_FragColor=fxaa(texture2D(Texture_First,TexCoord1),8.0);}\n'
out=root/'Artifacts/mobile-controls';out.mkdir(parents=True,exist_ok=True)
(out/'FXAAFragment.h').write_text('static const char *WrathSmokeFXAAFragment='+json.dumps(fragment)+';\n',encoding='utf-8')
(out/'fxaa-source.json').write_text(json.dumps({'pinned_kernel_sha256':hashlib.sha256(kernel.encode()).hexdigest(),'source':'shader_glsl.h::fxaa'},indent=2)+'\n',encoding='utf-8')
