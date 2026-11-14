#!/usr/bin/env python3
"""Extract only hash-pinned native libraries/notices; never the BCD app or game data."""
import hashlib, json, pathlib, sys, zipfile
manifest = json.loads(pathlib.Path(__file__).with_name('zink-native-inputs.json').read_text())
def digest(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda:f.read(1024*1024), b''): h.update(block)
    return h.hexdigest()
def extract(archive, out):
    if archive.stat().st_size != manifest['source_ipa_bytes'] or digest(archive) != manifest['source_ipa_sha256']:
        raise ValueError('Source IPA size/hash mismatch; refusing extraction')
    if out.exists(): raise ValueError('Use a fresh output directory')
    verified={}
    with zipfile.ZipFile(archive) as z:
        for relative, spec in manifest['files'].items():
            matches=[i for i in z.infolist() if i.filename==spec['source_member']]
            if len(matches)!=1 or matches[0].file_size!=spec['bytes']:
                raise ValueError('Missing/duplicate/size-mismatched member: '+relative)
            data=z.read(matches[0])
            if hashlib.sha256(data).hexdigest()!=spec['sha256']:
                raise ValueError('Member hash mismatch: '+relative)
            name=pathlib.PurePosixPath(relative).name
            if name in verified: raise ValueError('Duplicate output basename')
            verified[name]=data
    out.mkdir(parents=True)
    for name,data in verified.items(): (out/name).write_bytes(data)
    (out/'SHA256SUMS').write_text(''.join(hashlib.sha256(data).hexdigest()+'  '+name+'\n' for name,data in verified.items()))
    (out/'provenance.json').write_text(json.dumps(manifest,indent=2)+'\n')
    notes='Standalone renderer diagnostic dependency provenance\n'+json.dumps(manifest,indent=2)+'\n'
    for name,data in verified.items():
        if not name.endswith('.dylib'): notes+='\n===== '+name+' =====\n'+data.decode('utf-8')
    (out/'SOURCE_NOTICES.txt').write_text(notes)
if __name__=='__main__':
    if len(sys.argv)!=3: raise SystemExit('usage: extract_inputs.py PINNED_IPA NEW_OUTPUT_DIR')
    extract(pathlib.Path(sys.argv[1]),pathlib.Path(sys.argv[2]))
