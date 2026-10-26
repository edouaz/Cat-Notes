"""Package an archived .app without macOS AppleDouble/resource-fork entries."""
import os
from pathlib import Path
import stat
import sys
import zipfile


def package(app, output):
    app, output = Path(app), Path(output)
    if app.suffix != '.app' or not (app / 'Info.plist').is_file():
        raise ValueError('Expected an archived .app containing Info.plist')
    if output.exists():
        raise FileExistsError(output)
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
        payload = zipfile.ZipInfo('Payload/')
        payload.create_system = 3
        payload.external_attr = (stat.S_IFDIR | 0o755) << 16
        archive.writestr(payload, b'')
        archive.write(app, 'Payload/' + app.name + '/')
        for path in sorted(app.rglob('*')):
            relative = path.relative_to(app.parent)
            if any(part.startswith('._') or part in {'__MACOSX', '.DS_Store'} for part in relative.parts):
                continue
            name = 'Payload/' + relative.as_posix()
            if path.is_symlink():
                entry = zipfile.ZipInfo(name)
                entry.create_system = 3
                entry.external_attr = (stat.S_IFLNK | 0o777) << 16
                archive.writestr(entry, os.readlink(path))
            else:
                archive.write(path, name)
    with zipfile.ZipFile(output) as archive:
        assert archive.testzip() is None
        assert all(not any(part.startswith('._') or part == '__MACOSX' for part in name.split('/')) for name in archive.namelist())


if __name__ == '__main__':
    package(*sys.argv[1:])
