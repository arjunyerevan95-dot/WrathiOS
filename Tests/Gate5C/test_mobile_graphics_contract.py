#!/usr/bin/env python3
"""Check only changed scale policy and preservation of the GLES2 engine source."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess

ROOT=Path(__file__).resolve().parents[2]
BASE='b7321f7d702103a552bd45c070766f5ac2984aae'

def without_gles3(text):
    stack=[];out=[];active=True
    for line in text.splitlines():
        if re.match(r'\s*#\s*(if|ifdef|ifndef)\b',line):
            targeted=bool(re.match(r'\s*#\s*ifdef\s+WRATH_IOS_GLES3\s*$',line))
            stack.append((targeted,active))
            if targeted:active=False
            elif active:out.append(line)
        elif re.match(r'\s*#\s*(else|elif)\b',line):
            targeted,parent=stack[-1]
            if targeted:active=parent
            elif active:out.append(line)
        elif re.match(r'\s*#\s*endif\b',line):
            targeted,parent=stack.pop()
            if not targeted and active:out.append(line)
            active=parent
        elif active:out.append(line)
    assert not stack
    return re.findall(r'"(?:\\.|[^"\\])*"|\w+|[^\s]', '\n'.join(out))

def materialize(spec,path,source):
    text=(source/path).read_text(encoding='utf-8')
    for p in spec['patches']:
        if p['path']==path:
            for r in p['replacements']:
                assert text.count(r['old'])==1,(path,r['old'][:80])
                text=text.replace(r['old'],r['new'],1)
    return text

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine-source',type=Path,default=ROOT/'Vendor/wrath-darkplaces')
    parser.add_argument('--baseline-files',type=Path)
    parser.add_argument('--compiler',default=os.environ.get('CXX','c++'))
    parser.add_argument('--artifacts',type=Path,default=ROOT/'Artifacts/mobile-controls')
    args=parser.parse_args();args.artifacts.mkdir(parents=True,exist_ok=True)
    if args.baseline_files:
        baseline=json.loads(json.loads(args.baseline_files.read_text(encoding='utf-8'))['config/engine/ios_source_patches.json'])
    else:
        baseline=json.loads(subprocess.check_output(['git','-C',str(ROOT),'show',BASE+':config/engine/ios_source_patches.json']).decode('utf-8'))
    current=json.loads((ROOT/'config/engine/ios_source_patches.json').read_text(encoding='utf-8'))
    checked=[]
    for path in ['vid_sdl.c','vid_shared.c','model_brush.c','glquake.h']:
        old=materialize(baseline,path,args.engine_source);new=materialize(current,path,args.engine_source)
        assert without_gles3(old)==without_gles3(new),path
        checked.append(path)
    code=r'''
#include "WrathMobileGraphics.h"
#include <cassert>
#include <cmath>
int main(){
 assert(WrathMobileRenderScale(0,0)==.5);
 for(double v : {1.,.67,.5,.33})assert(WrathMobileRenderScale(1,v)==v);
 assert(WrathMobileRenderScale(1,NAN)==1.);
 assert(WrathMobileRenderScale(1,-1)==1.);
 assert(WrathMobileRenderScaleIndex(.33)==3);
 assert(WrathMobileRenderScaleIndex(.5)==2);
 assert(std::fabs(std::pow(WrathMobileRenderScale(1,.33),2)-.1089)<1e-9);
 assert(WrathMobileMSAASamples(0,4,1)==1);
 assert(WrathMobileMSAASamples(0,1,8)==8);
 for(int v : {1,2,4})assert(WrathMobileMSAASamples(1,v,2)==v);
 assert(WrathMobileMSAASamples(1,0,4)==4);
}
'''.replace('#include <cassert>','#include <cassert>\n#include <initializer_list>')
    src=args.artifacts/'mobile-policy.cpp';src.write_text(code,encoding='utf-8')
    exe=args.artifacts/('mobile-policy.exe' if os.name=='nt' else 'mobile-policy')
    if Path(args.compiler).stem.lower()=='cl':
        command=[args.compiler,'/nologo','/std:c++17','/W4','/WX','/EHsc','/I'+str(ROOT/'Gate5C'),str(src),'/Fe:'+str(exe),'/Fo:'+str(args.artifacts/'mobile-policy.obj')]
    else:command=[args.compiler,'-std=c++17','-Wall','-Wextra','-Werror','-I'+str(ROOT/'Gate5C'),str(src),'-o',str(exe)]
    subprocess.run(command,check=True);subprocess.run([str(exe.resolve())],check=True)
    receipt={'baseline':BASE,'gles2_engine_source_preserved':checked,
        'scale_policy':'Missing preference 0.5; saved Native/0.67/0.5/0.33 and legacy invalid-value behavior retained.',
        'msaa_policy':'Explicit supported native preference overrides; otherwise retain the configured engine sample count, including fallback.',
        'scope':'Changed policy and source preservation only; no performance or phone claim.'}
    (args.artifacts/'source-validation.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(receipt,indent=2))

if __name__=='__main__':main()
