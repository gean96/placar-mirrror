"""Incrementa android:versionCode no AndroidManifest.binario de um APK.

Usado pelo fast_push no Flet 0.86: serious_python so re-extrai assets/app.zip
quando versionName+versionCode muda. APKs release nao sao debuggable, entao
nao da para apagar files/flet/.key via adb run-as.
"""

from __future__ import annotations

import re
import struct
import sys
import zipfile
from pathlib import Path


def _find_version_code(manifest: bytes) -> tuple[int, int]:
    """Retorna (offset_do_Res_value, versionCode).

    Procura Res_value INT (type=0x10). No manifesto do Flet o primeiro INT
    tipico do bloco <manifest> e o versionCode.
    """
    for match in re.finditer(rb"\x08\x00\x00\x10(.{4})", manifest, flags=re.DOTALL):
        value = struct.unpack("<I", match.group(1))[0]
        if 1 <= value <= 2_000_000_000:
            return match.start(), value
    raise RuntimeError("Nao foi possivel localizar versionCode no AndroidManifest.binario")


def bump_apk(apk_path: Path, new_code: int | None = None) -> tuple[int, int]:
    with zipfile.ZipFile(apk_path, "r") as zin:
        if "AndroidManifest.xml" not in zin.namelist():
            raise RuntimeError("AndroidManifest.xml ausente no APK")
        manifest = bytearray(zin.read("AndroidManifest.xml"))
        offset, current = _find_version_code(bytes(manifest))
        target = new_code if new_code is not None else current + 1
        if target <= current:
            target = current + 1

        # Res_value.data (u32 LE) comeca 4 bytes apos o prefixo 08 00 00 10
        data_off = offset + 4
        old_pat = manifest[offset : offset + 8]
        expected = b"\x08\x00\x00\x10" + struct.pack("<I", current)
        if bytes(old_pat) != expected:
            raise RuntimeError("Padrao versionCode inconsistente no manifesto")
        manifest[data_off : data_off + 4] = struct.pack("<I", target)

        tmp = apk_path.with_suffix(".bump.tmp")
        with zipfile.ZipFile(tmp, "w") as zout:
            for info in zin.infolist():
                data = (
                    bytes(manifest)
                    if info.filename == "AndroidManifest.xml"
                    else zin.read(info.filename)
                )
                new_info = zipfile.ZipInfo(filename=info.filename, date_time=info.date_time)
                new_info.compress_type = info.compress_type
                new_info.external_attr = info.external_attr
                new_info.create_system = info.create_system
                zout.writestr(new_info, data)

    tmp.replace(apk_path)
    return current, target


def main() -> int:
    if len(sys.argv) < 2:
        print("Uso: apk_bump_version_code.py <apk> [novo_versionCode]", file=sys.stderr)
        return 2
    apk = Path(sys.argv[1])
    new_code = int(sys.argv[2]) if len(sys.argv) > 2 else None
    if not apk.is_file():
        print(f"APK nao encontrado: {apk}", file=sys.stderr)
        return 1
    old, new = bump_apk(apk, new_code)
    print(f"[apk_bump] versionCode {old} -> {new}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
