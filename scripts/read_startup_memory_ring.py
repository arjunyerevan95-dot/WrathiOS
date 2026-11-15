#!/usr/bin/env python3
"""Decode the bounded GLES3 startup evidence file copied from the app sandbox."""
import argparse
import json
from pathlib import Path

RECORD_BYTES=512
RECORD_SLOTS=256

def decode(data):
    if len(data)>RECORD_BYTES*RECORD_SLOTS:
        raise ValueError('File exceeds the startup ring limit')
    records=[]
    invalid=0
    for offset in range(0,len(data),RECORD_BYTES):
        slot=data[offset:offset+RECORD_BYTES]
        if not slot.strip(b'\0 \r\n'):
            continue
        try:
            if len(slot)!=RECORD_BYTES or slot[-1:]!=b'\n':
                raise ValueError('Partial record')
            row=json.loads(slot)
            if not isinstance(row['seq'],int) or row['seq']<0 or (row['seq']%RECORD_SLOTS)*RECORD_BYTES!=offset:
                raise ValueError('Sequence does not match slot')
            records.append(row)
        except (ValueError,KeyError,TypeError,UnicodeDecodeError):
            invalid+=1
    records.sort(key=lambda r:r['seq'])
    return {'records':records,'invalid_slots':invalid}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('path',type=Path)
    parser.add_argument('--summary',action='store_true')
    args=parser.parse_args()
    result=decode(args.path.read_bytes())
    if args.summary:
        rows=result.pop('records')
        result.update(count=len(rows),first=rows[0] if rows else None,last=rows[-1] if rows else None)
    print(json.dumps(result,indent=2))

if __name__=='__main__':
    main()
