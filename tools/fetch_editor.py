"""Optional standard Godot editor for native mobile exports from a Mono machine."""
from pathlib import Path
import zipfile
import fetch_templates as remote
remote.URL='https://github.com/godotengine/godot/releases/download/4.5.1-stable/Godot_v4.5.1-stable_win64.exe.zip'
dest=remote.ROOT/'tmp'/'godot';dest.mkdir(parents=True,exist_ok=True)
(dest.parent/'.gdignore').touch()
with zipfile.ZipFile(remote.RemoteZip()) as archive:
    for name in archive.namelist():
        if not name.endswith('.exe'):continue
        print('Fetching standard Godot:',name,flush=True)
        data=archive.read(name)
        (dest/Path(name).name).write_bytes(data)
        print('Verified ZIP entry:',name,len(data),flush=True)
