# Build with the pinned requirements-build.txt from the repository root.
from pathlib import Path

root = Path(SPECPATH).resolve().parents[1]
assets = root / 'tools/windows_score_uploader/assets'
a = Analysis([str(root/'tools/run_windows_score_uploader.py')],
    pathex=[str(root/'tools')],
    binaries=[], datas=[(str(assets), 'windows_score_uploader/assets')],
    hiddenimports=['serial.tools.list_ports_windows'],
    hookspath=[], runtime_hooks=[],
    excludes=['numpy', 'matplotlib', 'tkinter', 'PySide2', 'PySide6', 'PyQt6'],
    noarchive=False)
pyz = PYZ(a.pure)
exe = EXE(pyz, a.scripts, [], exclude_binaries=True,
    name='FPGA_Guitar_Uploader', debug=False, bootloader_ignore_signals=False,
    strip=False, upx=False, console=False, icon=str(assets/'guitar.ico'))
coll = COLLECT(exe, a.binaries, a.datas, strip=False, upx=False,
               name='FPGA_Guitar_Uploader')
