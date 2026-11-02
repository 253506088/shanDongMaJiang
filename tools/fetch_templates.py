"""Fetch selected official Godot export templates using verified ZIP entries.
HTTP ranges avoid downloading unrelated platform templates (~1.35 GB).
"""
import io, urllib.request, zipfile, concurrent.futures, hashlib, time
from pathlib import Path
URL='https://github.com/godotengine/godot/releases/download/4.5.1-stable/Godot_v4.5.1-stable_export_templates.tpz'
ROOT=Path(__file__).resolve().parents[1]
class RemoteZip(io.RawIOBase):
    def __init__(self):
        self.pos=0
        with urllib.request.urlopen(urllib.request.Request(URL,headers={'Range':'bytes=0-0'}),timeout=60) as r:
            self.length=int(r.headers['Content-Range'].split('/')[-1])
    def seekable(self):return True
    def readable(self):return True
    def tell(self):return self.pos
    def seek(self,offset,whence=0):
        self.pos=offset if whence==0 else self.pos+offset if whence==1 else self.length+offset
        return self.pos
    def read(self,n=-1):
        n=min(n if n>=0 else self.length-self.pos,self.length-self.pos)
        if n<=0:return b''
        start=self.pos; end=start+n-1
        def part(bounds):
            first,last=bounds
            cache=ROOT/'tmp'/'download_chunks'/hashlib.sha256(URL.encode()).hexdigest()[:16]
            cache.mkdir(parents=True,exist_ok=True)
            entry=cache/f'{first}-{last}.bin'
            if entry.exists() and entry.stat().st_size==last-first+1:return entry.read_bytes()
            for attempt in range(4):
                try:
                    req=urllib.request.Request(URL+'?range='+str(first),headers={'Range':f'bytes={first}-{last}'})
                    with urllib.request.urlopen(req,timeout=120) as r:
                        if r.status!=206:raise RuntimeError('Server did not honor HTTP range')
                        result=r.read()
                    if len(result)!=last-first+1:raise RuntimeError('Incomplete range download')
                    entry.write_bytes(result)
                    return result
                except Exception:
                    if attempt==3:raise
                    time.sleep(1+attempt)
        if n>2097152:
            ranges=[(p,min(end,p+2097151)) for p in range(start,end+1,2097152)]
            with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:data=b''.join(pool.map(part,ranges))
        else:data=part((start,end))
        if len(data)!=n:raise RuntimeError('Incomplete template download')
        self.pos+=n;return data
if __name__=='__main__':
    dest=ROOT/'tmp'/'export_templates';dest.mkdir(parents=True,exist_ok=True)
    (dest.parent/'.gdignore').touch()
    with zipfile.ZipFile(RemoteZip()) as z:
        names=['windows_release_x86_64.exe','windows_debug_x86_64.exe','android_debug.apk','android_release.apk','macos.zip','version.txt']
        for name in names:
            match=[n for n in z.namelist() if n.split('/')[-1]==name]
            if not match:print('NOT PRESENT',name,flush=True);continue
            target=dest/name
            if target.exists() and target.stat().st_size==z.getinfo(match[0]).file_size:continue
            print('Fetching',name,z.getinfo(match[0]).compress_size,'compressed bytes',flush=True)
            data=z.read(match[0]) # zipfile verifies each entry's CRC before writing.
            target.write_bytes(data)
            print('Fetched',name,len(data),flush=True)
