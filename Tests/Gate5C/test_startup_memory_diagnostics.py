#!/usr/bin/env python3
"""Exercise the bounded evidence format and preserve the delivered GLES2 code."""
from pathlib import Path
import argparse
import importlib.util
import json
import re
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
BASE='c3703223b311632dc059ff3b239aa0050f78a3f7'
ART=ROOT/'Artifacts/startup-memory'

def baseline_file(path,ref=BASE):
    return subprocess.check_output(['git','-C',str(ROOT),'show',f'{ref}:{path}']).decode('utf-8')

def materialize(spec,file,engine):
    text=(engine/file).read_text(encoding='utf-8')
    for patch in spec['patches']:
        if patch['path']==file:
            for replacement in patch['replacements']:
                old=replacement['old']
                assert text.count(old)==1,(file,old[:100])
                text=text.replace(old,replacement['new'],1)
    return text

def without_gles3_blocks(text):
    output=[]
    dropping=False
    for line in text.splitlines():
        if line=='#ifdef WRATH_IOS_GLES3':
            assert not dropping
            dropping=True
        elif dropping and line=='#endif':
            dropping=False
        elif not dropping:
            output.append(line)
    assert not dropping
    return '\n'.join(output)

def tokens(text):
    return re.sub(r'\s+','',text)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline-ref',default=BASE)
    parser.add_argument('--engine-source',type=Path,default=ROOT/'Vendor/wrath-darkplaces')
    parser.add_argument('--artifacts',type=Path,default=ART)
    args=parser.parse_args()
    baseline=json.loads(baseline_file('config/engine/ios_source_patches.json',args.baseline_ref))
    current=json.loads((ROOT/'config/engine/ios_source_patches.json').read_text(encoding='utf-8'))
    checks=[]
    for file in ['menu.c','gl_backend.c','gl_rmain.c','gl_textures.c','zone.c']:
        before=materialize(baseline,file,args.engine_source)
        after=materialize(current,file,args.engine_source)
        stripped,count=re.subn(r'\n#ifdef WRATH_IOS_GLES3 /\* startup memory evidence \*/\n.*?\n#endif /\* startup memory evidence \*/\n','',after,flags=re.S)
        assert count>0 and tokens(stripped)==tokens(before),file
        checks.append({'file':file,'GLES3_boundaries':count,'GLES2_original_tokens_preserved':True})
    for file in ['Gate5/WrathRuntime.mm','Gate5/WrathRuntimeHooks.h']:
        before=baseline_file(file,args.baseline_ref)
        after=without_gles3_blocks((ROOT/file).read_text(encoding='utf-8'))
        assert tokens(before)==tokens(after),file
        checks.append({'file':file,'GLES2_original_tokens_preserved':True})

    module=importlib.util.spec_from_file_location('ring',ROOT/'scripts/read_startup_memory_ring.py')
    decoder=importlib.util.module_from_spec(module)
    module.loader.exec_module(decoder)
    data=(args.artifacts/'test.ring').read_bytes()
    assert len(data)==512*256
    result=decoder.decode(data)
    assert result['invalid_slots']==0
    assert [r['seq'] for r in result['records']]==list(range(3840,4096))
    assert all(r['footprint']==6442456904 and r['thread']==17 for r in result['records'])
    extreme=json.loads((args.artifacts/'test.ring.extreme').read_bytes())
    assert extreme['seq']==2**64-1 and extreme['thread']==2**64-1
    assert extreme['a']==-(2**63) and extreme['b']==2**63-1 and extreme['valid'] is False
    assert extreme['detail']=='quotes_and-newline_.c'
    partial=decoder.decode(data[:-1])
    assert partial['invalid_slots']==1 and len(partial['records'])==255
    assert decoder.decode(bytes(512))=={'records':[],'invalid_slots':0}
    try:
        decoder.decode(bytes(512*256+1))
    except ValueError:
        pass
    else:
        raise AssertionError('Oversized evidence accepted')
    receipt={'baseline':args.baseline_ref,'source_checks':checks,
        'ring_checks':{'writes':4096,'retained':256,'bytes':131072,'counter_extremes':True,'partial_records':True,'source_path_removal':True},
        'scope':'Startup diagnostics only. No full-engine startup or phone validation claimed.'}
    (args.artifacts/'validation.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(receipt,indent=2))
    return 0

if __name__=='__main__':
    sys.exit(main())
