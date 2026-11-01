#!/usr/bin/env python3
"""按 deps.json 装配一加 13T（PKX110 / sun / sm8750）官方内核构建树。

用法（在 Linux / WSL2 里跑）：
    python3 assemble.py --root ./oneplus13t-kernel --jobs 6

做的事：
  1) 并发下载 35 个依赖到 --arch-dir（默认 <root>/../_dl），已存在且可完整解压的跳过
  2) release-mirror 源严格校验 size + sha256；GitHub /archive/<sha>.tar.gz 是非确定性
     打包，字节数每包都会漂移，只能以"能完整解压"为完整性判据
  3) 剥掉每个归档的单一顶级前缀，解到 deps.json 里的 path
  4) 补上 prepare_vendor.sh 才创建、但配置门禁步骤会跳过的软链接
  5) 报告体积与剩余空间（官方口径：< 25 GiB 可能编挂）

依赖：python3 标准库即可，无需 git。
"""

from __future__ import annotations

import argparse
import hashlib
import os
import shutil
import sys
import tarfile
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEPS = HERE / "deps.json"

# prepare_vendor.sh 正常会创建，但独立跑 bazel 时必须自己补
SYMLINKS = [
    ("kernel_platform/.source_date_epoch_dir", "common"),
    ("kernel_platform/build_with_bazel.py", "msm-kernel/build_with_bazel.py"),
    ("kernel_platform/build/msm_kernel_extensions.bzl", "../msm-kernel/msm_kernel_extensions.bzl"),
    ("kernel_platform/build/abl_extensions.bzl", "../bootable/bootloader/edk2/abl_extensions.bzl"),
]
# 这 4 个链接的源（相对 link 所在目录）若不存在就跳过，不报错


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(8 * 1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def archive_ok(path: Path) -> bool:
    try:
        with tarfile.open(path, "r|gz") as tf:
            if tf.next() is None:
                return False
            for _ in tf:
                pass
        return True
    except Exception:
        return False


def verify(dep: dict, path: Path) -> str | None:
    if path.stat().st_size != dep["bytes"]:
        # release-mirror 必须严格一致；git archive 允许漂移
        if dep.get("source") == "release-mirror":
            return f"size {path.stat().st_size} != {dep['bytes']}"
        return None if archive_ok(path) else "decompress failed"
    if dep.get("source") == "release-mirror":
        actual = sha256_of(path)
        if actual != dep["sha256"]:
            return f"sha256 {actual[:16]} != {dep['sha256'][:16]}"
    return None


def fetch(dep: dict, arch: Path) -> tuple[str, str, int]:
    dst = arch / (dep["name"].replace("/", "_") + ".tar.gz")
    if dst.exists() and verify(dep, dst) is None:
        return dep["name"], "cached", dst.stat().st_size
    if dst.exists():
        dst.unlink()
    last = ""
    for attempt in range(4):
        try:
            req = urllib.request.Request(dep["url"], headers={"User-Agent": "curl/8.4.0"})
            with urllib.request.urlopen(req, timeout=1800) as r, dst.open("wb") as f:
                shutil.copyfileobj(r, f, 4 * 1024 * 1024)
            problem = verify(dep, dst)
            if problem is None:
                return dep["name"], "ok", dst.stat().st_size
            last = problem
        except Exception as exc:  # noqa: BLE001
            last = str(exc)[:120]
        time.sleep(2 * (attempt + 1))
    raise RuntimeError(f"download failed {dep['name']}: {last}")


def assemble(dep: dict, arch: Path, root: Path) -> None:
    src = arch / (dep["name"].replace("/", "_") + ".tar.gz")
    dest_rel = dep["path"]
    dest = root / dest_rel
    dest.mkdir(parents=True, exist_ok=True)
    written = 0
    with tarfile.open(src, "r|gz") as tf:
        prefix = None
        for member in tf:
            first, sep, relative = member.name.partition("/")
            if prefix is None:
                prefix = first
            if first != prefix:
                raise RuntimeError(f"archive has multiple top prefixes: {dep['name']}")
            if not sep or not relative:
                continue
            member.name = (Path(dest_rel) / relative).as_posix()
            if member.islnk() and member.linkname.startswith(prefix + "/"):
                member.linkname = (Path(dest_rel) / member.linkname[len(prefix) + 1:]).as_posix()
            target = root / member.name
            if os.path.lexists(target):
                continue
            # filter="data"（py>=3.12 的默认行为）会拒绝"剥掉一层前缀后指向树外"的相对软链，
            # 例如 kernel_platform/build/android/export_headers.py -> ../../../kernel/...。
            # 这些链接是官方 tar 按"带顶层目录"拍的相对路径，剥前缀后必然错位；
            # 它们只影响导航便利性、不影响编译，所以用 fully_trusted 原样解出。
            try:
                tf.extract(member, path=root, filter="fully_trusted")
            except TypeError:  # py < 3.12 没有 filter 参数
                tf.extract(member, path=root)
            written += 1
    print(f"  assembled {dep['name']:<58} -> {dest_rel}  ({written} entries)", flush=True)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default="./oneplus13t-kernel", help="装配输出的构建树根目录")
    ap.add_argument("--arch-dir", default=None, help="归档缓存目录，默认 <root>/../_dl")
    ap.add_argument("--jobs", type=int, default=6)
    ap.add_argument("--only", default=None, help="只装名字包含该子串的依赖（补装用）")
    args = ap.parse_args()

    if not DEPS.exists():
        print(f"deps.json not found next to script: {DEPS}", file=sys.stderr)
        return 2

    import json

    deps = json.loads(DEPS.read_text(encoding="utf-8"))
    root = Path(args.root).resolve()
    arch = Path(args.arch_dir).resolve() if args.arch_dir else root.parent / "_dl"
    root.mkdir(parents=True, exist_ok=True)
    arch.mkdir(parents=True, exist_ok=True)

    if args.only:
        deps = [d for d in deps if args.only in d["name"]]

    total_gib = sum(d["bytes"] for d in deps) / 1024 ** 3
    print(f"{len(deps)} deps, {total_gib:.2f} GiB, root={root}")
    free = shutil.disk_usage(root).free / 1024 ** 3
    print(f"free space: {free:.1f} GiB")
    if free < 25:
        print("WARNING: < 25 GiB free, build will likely fail")

    t0 = time.time()
    with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as ex:
        results = list(ex.map(lambda d: fetch(d, arch), deps))
    drift = [(d, s) for d, (_, _, s) in zip(deps, results)
             if d.get("source") != "release-mirror" and s != d["bytes"]]
    if drift:
        print(f"note: {len(drift)} GitHub archives differ in size from deps.json "
              f"(non-deterministic packing, expected)")
    print(f"download done in {time.time() - t0:.0f}s, assembling...")

    # 先装 ./ 那条（modules 仓，提供 kernel_platform/build、oplus、vendor）
    for dep in sorted(deps, key=lambda d: (d["path"] != "./", d["path"])):
        assemble(dep, arch, root)

    for link, target in SYMLINKS:
        p = root / link
        if os.path.lexists(p):
            continue
        source = (p.parent / target)
        if not source.exists():
            print(f"  skip symlink (missing source): {link}")
            continue
        p.parent.mkdir(parents=True, exist_ok=True)
        p.symlink_to(target)
        print(f"  symlink: {link} -> {target}")

    files = sum(1 for _ in root.rglob("*"))
    print(f"done. {files} entries, free space {shutil.disk_usage(root).free / 1024 ** 3:.1f} GiB")
    print("\nnext:\n  cd %s\n  bash kernel_platform/oplus/build/oplus_build_kernel.sh sun perf" % root)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
