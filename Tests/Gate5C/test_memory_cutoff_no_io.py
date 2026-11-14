from pathlib import Path
s=(Path(__file__).resolve().parents[2]/'Gate5C/WrathZinkBridge.mm').read_text()
sample=s.split('static bool WrathMemorySample(void) {',1)[1].split('static void WrathMemoryWriteLastSample',1)[0]
for banned in ['pwrite(', 'ftruncate(', 'fsync(', 'dispatch_sync(', 'WrathMemoryWriteLastSample(']:
 assert banned not in sample,banned
assert 'dispatch_source_set_event_handler(memoryTimer,^{if(!WrathMemorySample())_Exit(78);});' in s
assert 'dispatch_source_set_event_handler(memoryLogTimer,^{WrathMemoryWriteLastSample();});' in s
assert 'fsync(' not in s
print('Cutoff samples and exits without filesystem work; logging isolated on separate queue')
