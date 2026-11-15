#!/usr/bin/env python3
"""Reuse exact passed checks only when the repair changes no runtime/test source."""
import hashlib
import json
from pathlib import Path, PurePosixPath
import subprocess
import zipfile

ROOT=Path(__file__).resolve().parents[1]
BASE='5781e0c971b3bbb2d0820c5c7157db1d249b23a6'
RUN=43735839779
ARTIFACT=14171240059
DIGEST='04ce867117f39711fca6b0094522dbbbff70d872bc48ecef958b9a3a901b769b'
REPO='arjunyerevan95-dot/WrathiOS'
OUT=ROOT/'Artifacts/mobile-controls'

def api(path):return json.loads(subprocess.check_output(['gh','api',f'repos/{REPO}/{path}']).decode('utf-8'))
def git(*args):return subprocess.check_output(['git','-C',str(ROOT),*args]).decode('utf-8')
def normalize(spec):
    spec=json.loads(json.dumps(spec))
    for p in spec['patches']:p.pop('reason',None)
    return spec

changed=set(git('diff','--name-only',BASE,'HEAD').splitlines())
allowed={'config/engine/ios_source_patches.json','.github/workflows/gles3-startup-diagnostic.yml','scripts/reuse_mobile_smoke.py'}
assert changed<=allowed,('Runtime/test source changed; rerun affected checks instead of reusing them.',changed-allowed)
before=json.loads(git('show',BASE+':config/engine/ios_source_patches.json'))
after=json.loads((ROOT/'config/engine/ios_source_patches.json').read_text(encoding='utf-8'))
assert normalize(before)==normalize(after),'Source replacement or source pin changed'
assert all(p.get('reason') and p['path'] and p['replacements'] for p in after['patches'])
run=api(f'actions/runs/{RUN}');assert run['head_sha']==BASE and run['status']=='completed'
jobs=api(f'actions/runs/{RUN}/jobs')['jobs'];assert len(jobs)==1
steps={s['name']:s['conclusion'] for s in jobs[0]['steps']}
for name in ['Check changed mobile graphics policy and GLES2 preservation','Smoke changed settings, Artifact input and MSAA-FXAA GPU path']:
    assert steps[name]=='success',(name,steps.get(name))
artifact=next(a for a in api(f'actions/runs/{RUN}/artifacts')['artifacts'] if a['id']==ARTIFACT)
assert artifact['name']=='wrath-gles3-mobile-controls' and not artifact['expired']
assert artifact['digest']=='sha256:'+DIGEST
OUT.mkdir(parents=True,exist_ok=True)
archive=OUT/'passed-checks.zip'
with archive.open('wb') as handle:subprocess.run(['gh','api',f'repos/{REPO}/actions/artifacts/{ARTIFACT}/zip'],stdout=handle,check=True)
assert hashlib.sha256(archive.read_bytes()).hexdigest()==DIGEST
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    for name in z.namelist():assert not PurePosixPath(name).is_absolute() and '..' not in PurePosixPath(name).parts and '\\' not in name
    for name in ['source-validation.json','mobile-smoke.json','fxaa-source.json']:
        (OUT/name).write_bytes(z.read('mobile-controls/'+name))
smoke=json.loads((OUT/'mobile-smoke.json').read_text())
assert smoke['passed'] is True and smoke['phoneTested'] is False and smoke['actualMSAASamples']>1
assert len(smoke['checks'])==6,smoke
receipt={'source_commit':BASE,'source_run':RUN,'source_artifact':ARTIFACT,'zip_sha256':DIGEST,
    'checked_changes':sorted(changed),'runtime_and_test_sources_identical':True,
    'engine_replacements_identical':True,'reason':'Only patch provenance descriptions and workflow/reuse plumbing changed.',
    'scope':'Passed native checks reused; no new simulator run or performance claim.'}
(OUT/'reused-checks-provenance.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'provenance':receipt,'native_smoke':smoke},indent=2))
