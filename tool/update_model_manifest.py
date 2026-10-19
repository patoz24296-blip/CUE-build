"""Refresh pinned upstream file digests; run only when updating model revisions."""
import json
import urllib.request
import urllib.parse
from pathlib import Path

SPECS = [
    ('whisper-multilingual', 'Multilingual recognition', 'Whisper tiny · choose a language, lower memory', 'csukuangfj/sherpa-onnx-whisper-tiny', '65176e2deb88badc814a94058666cadccc29b61c', lambda p: p.endswith('.int8.onnx') or p.endswith('-tokens.txt')),
    ('whisper-small', 'High-quality recognition', 'English · larger model for devices with more memory', 'csukuangfj/sherpa-onnx-whisper-small.en', 'd9533f69affd85061aee349af7fea5cb2996dbbe', lambda p: p.endswith('.int8.onnx') or p.endswith('-tokens.txt')),
    ('embeddings', 'Phrase comparison', 'Optional · local semantic evidence; protected information remains authoritative', 'nomic-ai/nomic-embed-text-v1.5-GGUF', '0188c9bf409793f810680a5a431e7b899c46104c', lambda p: p == 'nomic-embed-text-v1.5.Q4_K_M.gguf'),
    ('whisper-tiny', 'Quick recognition', 'English · lowest memory, fastest', 'csukuangfj/sherpa-onnx-whisper-tiny.en', 'd026532c022fa99fd789d6b32446a1df7b6bfc43', lambda p: p.endswith('.int8.onnx') or p.endswith('-tokens.txt')),
    ('whisper-base', 'Detailed recognition', 'English · more memory, better recognition', 'csukuangfj/sherpa-onnx-whisper-base.en', '59eea950fc76df2453efb57e6c0fd334548e8ffe', lambda p: p.endswith('.int8.onnx') or p.endswith('-tokens.txt')),
    ('voices', 'Scene partner voices', 'English · 904 local neural voices', 'csukuangfj/vits-piper-en_US-libritts_r-medium', 'fe872db7e697e9f2a45d09328953f1fd2a9df630', lambda p: p.endswith('.onnx') or p == 'tokens.txt' or p == 'MODEL_CARD' or p.startswith('espeak-ng-data/')),
    ('meaning', 'Meaning comparison', 'Optional · 0.5B model, broader paraphrases need review', 'Qwen/Qwen2.5-0.5B-Instruct-GGUF', '9217f5db79a29953eb74d5343926648285ec7e67', lambda p: p.lower() == 'qwen2.5-0.5b-instruct-q4_k_m.gguf' or p == 'LICENSE'),
]

def main():
    models = []
    for model_id, name, detail, repo, revision, include in SPECS:
        url = f'https://huggingface.co/api/models/{repo}/tree/{revision}?recursive=true&limit=1000'
        files = []
        while url:
            with urllib.request.urlopen(url) as response:
                entries = json.load(response)
                links = response.headers.get('Link', '')
            for entry in entries:
                if entry['type'] != 'file' or not include(entry['path']):
                    continue
                lfs = entry.get('lfs')
                files.append(dict(path=entry['path'], bytes=entry['size'],
                    digest=lfs['oid'] if lfs else entry['oid'], algorithm='sha256' if lfs else 'git-sha1',
                    url=f'https://huggingface.co/{repo}/resolve/{revision}/{urllib.parse.quote(entry["path"])}'))
            import re
            match = re.search(r'<([^>]+)>; rel="next"', links)
            url = match.group(1) if match else None
        if not files:
            raise RuntimeError(f'No files for {model_id}')
        models.append(dict(id=model_id, name=name, detail=detail, files=files, bytes=sum(f['bytes'] for f in files)))
        print(model_id, len(files), models[-1]['bytes'])
    # Silero comes from the maintainer's pinned model repo, with immutable digests.
    import hashlib
    url = 'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx'
    with urllib.request.urlopen(url) as r:
        data = r.read()
    models.append(dict(id='vad', name='Listening detector', detail='Silero · distinguishes speech from pauses', bytes=len(data), files=[dict(path='silero_vad.onnx', bytes=len(data), digest=hashlib.sha256(data).hexdigest(), algorithm='sha256', url=url)]))
    target = Path(__file__).resolve().parents[1] / 'assets' / 'models.json'
    target.write_text(json.dumps(models, indent=2) + '\n', encoding='utf-8', newline='\n')

if __name__ == '__main__':
    main()
