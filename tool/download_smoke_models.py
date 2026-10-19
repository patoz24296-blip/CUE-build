"""Fetch checksum-verified files for the opt-in native speech smoke test."""
import concurrent.futures
import hashlib
import json
import urllib.request
import urllib.parse
import os
import time
from pathlib import Path

root = Path(os.environ.get('CUE_SMOKE_MODELS', str(Path(__file__).resolve().parents[2] / '.tools' / 'smoke-models')))
catalog = json.loads((Path(__file__).resolve().parents[1] / 'assets' / 'models.json').read_text())

def download(job):
    folder, spec = job
    target = root / folder / spec['path']
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists() and target.stat().st_size == spec['bytes']:
        data = target.read_bytes()
    else:
        for attempt in range(4):
            try:
                request = urllib.request.Request(urllib.parse.quote(spec['url'], safe=':/%'), headers={'User-Agent': 'CUE-model-verification'})
                with urllib.request.urlopen(request, timeout=90) as response:
                    data = response.read()
                break
            except OSError:
                if attempt == 3: raise
                time.sleep(1 + attempt)
    digest = hashlib.sha256(data).hexdigest() if spec['algorithm'] == 'sha256' else hashlib.sha1(f'blob {len(data)}\0'.encode() + data).hexdigest()
    assert len(data) == spec['bytes'] and digest == spec['digest'], target
    target.write_bytes(data)

selection = set(os.environ.get('CUE_SMOKE_COMPONENTS', 'whisper-tiny,vad,voices').split(','))
jobs = [(model['id'], file) for model in catalog if model['id'] in selection for file in model['files']]
with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
    list(pool.map(download, jobs))
url = 'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny.en/resolve/d026532c022fa99fd789d6b32446a1df7b6bfc43/test_wavs/0.wav'
with urllib.request.urlopen(url) as response:
    (root / 'input.wav').write_bytes(response.read())
print(f'Verified {len(jobs)} model files in {root}')
