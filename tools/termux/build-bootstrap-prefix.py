#!/usr/bin/env python3
import os
import re
import shlex
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import textwrap
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


TERMUX_REPO = os.environ.get("MIRA_TERMUX_REPO", "https://packages-cf.termux.dev/apt/termux-main")
TARGET_ABI = "arm64-v8a"
TERMUX_PREFIX_PATH = "/data/data/com.termux/files/usr"
MIRA_PREFIX_PATH = "/data/data/com.vwww.mira/files/usr"
ROOT_PACKAGES = ("python", "python-pip")
PURE_PYTHON_SPECS = (
    "colorama<1.0.0,>=0.2.7",
    "prompt-toolkit<4.0.0,>=2.0.0",
    "pygments<3.0.0,>=2.0.2",
    "wcwidth",
)
EXPECTED_IMPORTS = ("frida_tools", "colorama", "prompt_toolkit", "pygments", "wcwidth", "pip")

SCRIPT_PATH = Path(__file__).resolve()
ROOT_DIR = SCRIPT_PATH.parents[2]
FRIDA_TOOLS_DIR = ROOT_DIR / "third_party" / "frida-tools"
DEFAULT_OUT_ROOT = ROOT_DIR / "android" / "app" / "build" / "generated" / "mira-toolbox-assets"
BUILD_ROOT = ROOT_DIR / "build" / "termux-prefix"
DEB_CACHE_DIR = BUILD_ROOT / "debs"
WHEEL_CACHE_DIR = BUILD_ROOT / "wheels"
INDEX_CACHE_PATH = BUILD_ROOT / "Packages.aarch64"


@dataclass(frozen=True)
class PackageInfo:
    name: str
    version: str
    filename: str
    depends: tuple[tuple[str, ...], ...]

    @property
    def url(self) -> str:
        return f"{TERMUX_REPO}/{self.filename}"


def log(message: str) -> None:
    print(f"[mira-termux] {message}", flush=True)


def run(cmd: list[str], **kwargs) -> None:
    log("run: " + " ".join(shlex.quote(part) for part in cmd))
    subprocess.run(cmd, check=True, **kwargs)


def fetch(url: str, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    run(
        [
            "curl",
            "-L",
            "--fail",
            "--retry",
            "3",
            "--continue-at",
            "-",
            "-o",
            str(destination),
            url,
        ]
    )


def read_package_index() -> str:
    fetch(f"{TERMUX_REPO}/dists/stable/main/binary-aarch64/Packages", INDEX_CACHE_PATH)
    return INDEX_CACHE_PATH.read_text(encoding="utf-8")


def parse_package_index(raw_text: str) -> dict[str, PackageInfo]:
    packages: dict[str, PackageInfo] = {}
    for block in raw_text.strip().split("\n\n"):
        if not block.strip():
            continue
        fields: dict[str, str] = {}
        current_key: str | None = None
        for line in block.splitlines():
            if line.startswith(" "):
                if current_key is None:
                    raise ValueError(f"无效的 Packages 字段续行: {line!r}")
                fields[current_key] += "\n" + line[1:]
                continue
            key, value = line.split(":", 1)
            current_key = key
            fields[key] = value.lstrip()
        name = fields.get("Package")
        filename = fields.get("Filename")
        version = fields.get("Version")
        if not name or not filename or not version:
            continue
        packages[name] = PackageInfo(
            name=name,
            version=version,
            filename=filename,
            depends=parse_depends(fields.get("Depends", "")),
        )
    return packages


def parse_depends(raw_depends: str) -> tuple[tuple[str, ...], ...]:
    groups: list[tuple[str, ...]] = []
    for group in raw_depends.split(","):
        group = group.strip()
        if not group:
            continue
        alternatives: list[str] = []
        for choice in group.split("|"):
            choice = re.sub(r"\s*\(.*?\)", "", choice).strip()
            if not choice:
                continue
            choice = choice.split(":", 1)[0].strip()
            if choice:
                alternatives.append(choice)
        if alternatives:
            groups.append(tuple(alternatives))
    return tuple(groups)


def resolve_packages(index: dict[str, PackageInfo], root_packages: Iterable[str]) -> list[PackageInfo]:
    ordered: list[PackageInfo] = []
    visiting: set[str] = set()
    resolved: set[str] = set()

    def visit(package_name: str) -> None:
        if package_name in resolved:
            return
        if package_name in visiting:
            raise RuntimeError(f"发现循环依赖: {package_name}")
        info = index.get(package_name)
        if info is None:
            raise KeyError(f"Packages 索引中缺少依赖: {package_name}")
        visiting.add(package_name)
        for group in info.depends:
            selected = next((candidate for candidate in group if candidate in index), None)
            if selected is None:
                raise KeyError(f"无法解析 {package_name} 的依赖候选: {' | '.join(group)}")
            visit(selected)
        visiting.remove(package_name)
        resolved.add(package_name)
        ordered.append(info)

    for package_name in root_packages:
        visit(package_name)
    return ordered


def deb_member_bytes(deb_path: Path, prefix: str) -> tuple[str, bytes]:
    with deb_path.open("rb") as handle:
        if handle.read(8) != b"!<arch>\n":
            raise ValueError(f"不是合法的 deb/ar 文件: {deb_path}")
        while True:
            header = handle.read(60)
            if not header:
                break
            if len(header) != 60:
                raise ValueError(f"deb 成员头损坏: {deb_path}")
            name = header[:16].decode("utf-8", errors="replace").strip()
            name = name.rstrip("/")
            size = int(header[48:58].decode("ascii").strip())
            payload = handle.read(size)
            if size % 2 == 1:
                handle.read(1)
            if name.startswith(prefix):
                return name, payload
    raise KeyError(f"{deb_path} 中缺少 {prefix} 成员")


def extract_deb(deb_path: Path, destination: Path) -> None:
    member_name, payload = deb_member_bytes(deb_path, "data.tar.")
    destination.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(prefix="mira-termux-data-", suffix="-" + member_name, delete=False) as handle:
        handle.write(payload)
        archive_path = Path(handle.name)
    try:
        try:
            run(["tar", "-xf", str(archive_path), "-C", str(destination)])
        except subprocess.CalledProcessError:
            with tarfile.open(archive_path, mode="r:*") as archive:
                archive.extractall(destination)
    finally:
        archive_path.unlink(missing_ok=True)


def find_raw_prefix(raw_root: Path) -> Path:
    candidates = (
        raw_root / "data" / "data" / "com.termux" / "files" / "usr",
        raw_root / "." / "data" / "data" / "com.termux" / "files" / "usr",
        raw_root / "usr",
        raw_root / "." / "usr",
    )
    for candidate in candidates:
        if candidate.exists():
            return candidate
    for candidate in raw_root.rglob("usr"):
        if candidate.is_dir() and (candidate / "bin").exists():
            return candidate
    raise FileNotFoundError(f"未找到 Termux prefix 根目录: {raw_root}")


def reset_directory(path: Path) -> None:
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)


def copy_dereferenced_tree(source_root: Path, destination_root: Path) -> None:
    seen_real_dirs: set[str] = set()
    for dirpath, dirnames, filenames in os.walk(source_root, topdown=True, followlinks=True):
        dir_path = Path(dirpath)
        real_dir = os.path.realpath(dir_path)
        if real_dir in seen_real_dirs:
            dirnames[:] = []
            continue
        seen_real_dirs.add(real_dir)

        relative_dir = dir_path.relative_to(source_root)
        target_dir = destination_root / relative_dir
        target_dir.mkdir(parents=True, exist_ok=True)

        for name in filenames:
            source_file = dir_path / name
            target_file = target_dir / name
            if source_file.is_symlink():
                resolved = Path(os.path.realpath(source_file))
                if not resolved.exists():
                    log(f"skip broken symlink: {source_file} -> {source_file.readlink()}")
                    continue
                shutil.copy2(resolved, target_file, follow_symlinks=True)
                source_mode = resolved.stat().st_mode
            else:
                shutil.copy2(source_file, target_file, follow_symlinks=True)
                source_mode = source_file.stat().st_mode
            os.chmod(target_file, stat.S_IMODE(source_mode))


def detect_python_version(prefix_root: Path) -> str:
    candidates = sorted(
        path.name
        for path in (prefix_root / "lib").glob("python*")
        if path.is_dir() and re.fullmatch(r"python\d+\.\d+", path.name)
    )
    if not candidates:
        raise FileNotFoundError(f"在 {prefix_root / 'lib'} 下未找到 pythonX.Y 目录")
    return candidates[-1].removeprefix("python")


def site_packages_dir(prefix_root: Path, python_version: str) -> Path:
    return prefix_root / "lib" / f"python{python_version}" / "site-packages"


def download_wheels(destination: Path) -> list[Path]:
    destination.mkdir(parents=True, exist_ok=True)
    before = {path.resolve() for path in destination.glob("*.whl")}
    run(
        [
            sys.executable,
            "-m",
            "pip",
            "download",
            "--disable-pip-version-check",
            "--only-binary=:all:",
            "--no-deps",
            "--dest",
            str(destination),
            *PURE_PYTHON_SPECS,
        ]
    )
    after = sorted({path.resolve() for path in destination.glob("*.whl")} - before)
    if not after:
        after = sorted(path.resolve() for path in destination.glob("*.whl"))
    return list(after)


def install_wheel(wheel_path: Path, site_packages: Path) -> None:
    with zipfile.ZipFile(wheel_path) as archive:
        for entry in archive.infolist():
            name = entry.filename
            if name.endswith("/"):
                continue
            parts = Path(name).parts
            if not parts:
                continue
            if parts[0].endswith(".data"):
                if len(parts) < 3 or parts[1] not in {"purelib", "platlib"}:
                    continue
                relative_target = Path(*parts[2:])
            else:
                relative_target = Path(*parts)
            target_path = site_packages / relative_target
            target_path.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(entry, "r") as source, target_path.open("wb") as target:
                shutil.copyfileobj(source, target)


def install_pure_python_dependencies(site_packages: Path) -> list[str]:
    wheel_paths = download_wheels(WHEEL_CACHE_DIR)
    installed: list[str] = []
    for wheel_path in wheel_paths:
        install_wheel(wheel_path, site_packages)
        installed.append(wheel_path.name)
    return installed


def copytree_replace(source: Path, destination: Path) -> None:
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(source, destination)


def install_vendored_frida_tools(site_packages: Path) -> None:
    if not FRIDA_TOOLS_DIR.is_dir():
        raise FileNotFoundError(f"缺少 vendored frida-tools: {FRIDA_TOOLS_DIR}")
    copytree_replace(FRIDA_TOOLS_DIR / "frida_tools", site_packages / "frida_tools")
    copytree_replace(FRIDA_TOOLS_DIR / "frida_tools.egg-info", site_packages / "frida_tools.egg-info")


def write_text_executable(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    path.chmod(0o755)


def ensure_python_entrypoints(prefix_root: Path, python_version: str) -> None:
    bin_dir = prefix_root / "bin"
    versioned_python = bin_dir / f"python{python_version}"
    if not versioned_python.exists():
        raise FileNotFoundError(f"缺少 Python 可执行文件: {versioned_python}")

    python3 = bin_dir / "python3"
    if not python3.exists():
        shutil.copy2(versioned_python, python3, follow_symlinks=True)
        python3.chmod(0o755)

    python_generic = bin_dir / "python"
    if not python_generic.exists():
        shutil.copy2(python3, python_generic, follow_symlinks=True)
        python_generic.chmod(0o755)

    pip_wrapper = textwrap.dedent(
        """\
        #!/system/bin/sh
        SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
        PYTHON_BIN="$SELF_DIR/python3"
        exec "$PYTHON_BIN" -m pip "$@"
        """
    )
    for name in ("pip", "pip3", f"pip{python_version}"):
        write_text_executable(bin_dir / name, pip_wrapper)


def write_source_manifest(asset_root: Path, packages: list[PackageInfo], wheels: list[str], python_version: str) -> None:
    lines = [
        f"termux-repo: {TERMUX_REPO}",
        f"target-abi: {TARGET_ABI}",
        f"python-version: {python_version}",
        f"relocated-prefix: {TERMUX_PREFIX_PATH} -> {MIRA_PREFIX_PATH}",
        "packages:",
    ]
    for package in packages:
        lines.append(f"  - {package.name} {package.version} {package.filename}")
    lines.append("python-wheels:")
    for wheel in wheels:
        lines.append(f"  - {wheel}")
    lines.append(f"vendored-frida-tools: {FRIDA_TOOLS_DIR}")
    (asset_root / "SOURCE.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")


def validate_layout(prefix_root: Path, python_version: str) -> None:
    site_packages = site_packages_dir(prefix_root, python_version)
    required_paths = (
        prefix_root / "bin" / "python3",
        prefix_root / "bin" / "pip",
        site_packages / "frida_tools" / "__init__.py",
        site_packages / "pip" / "__init__.py",
    )
    for path in required_paths:
        if not path.exists():
            raise FileNotFoundError(f"构建结果缺少必需文件: {path}")

    import_program = (
        "import sys; "
        f"sys.path.insert(0, {site_packages.as_posix()!r}); "
        "import " + ", ".join(EXPECTED_IMPORTS)
    )
    run([sys.executable, "-c", import_program])


def relocate_text_prefixes(prefix_root: Path) -> int:
    old_bytes = TERMUX_PREFIX_PATH.encode("utf-8")
    replaced = 0

    for path in prefix_root.rglob("*"):
        if not path.is_file():
            continue
        try:
            content = path.read_bytes()
        except OSError:
            continue
        if old_bytes not in content or b"\x00" in content:
            continue
        try:
            text = content.decode("utf-8")
        except UnicodeDecodeError:
            continue
        updated = text.replace(TERMUX_PREFIX_PATH, MIRA_PREFIX_PATH)
        if updated == text:
            continue
        path.write_text(updated, encoding="utf-8")
        replaced += 1

    return replaced


def build(out_root: Path) -> Path:
    asset_root = out_root / "bootstrap" / "prefix" / TARGET_ABI
    work_root = BUILD_ROOT / TARGET_ABI
    raw_root = work_root / "raw"

    log(f"output root: {asset_root}")
    package_index = parse_package_index(read_package_index())
    packages = resolve_packages(package_index, ROOT_PACKAGES)
    log("resolved packages: " + ", ".join(package.name for package in packages))

    reset_directory(raw_root)
    reset_directory(asset_root)

    for package in packages:
        deb_name = Path(package.filename).name
        deb_path = DEB_CACHE_DIR / deb_name
        fetch(package.url, deb_path)
        extract_deb(deb_path, raw_root)

    prefix_source = find_raw_prefix(raw_root)
    copy_dereferenced_tree(prefix_source, asset_root)

    python_version = detect_python_version(asset_root)
    site_packages = site_packages_dir(asset_root, python_version)
    site_packages.mkdir(parents=True, exist_ok=True)

    wheels = install_pure_python_dependencies(site_packages)
    install_vendored_frida_tools(site_packages)
    ensure_python_entrypoints(asset_root, python_version)
    relocated_files = relocate_text_prefixes(asset_root)
    log(f"relocated text files: {relocated_files}")
    write_source_manifest(asset_root, packages, wheels, python_version)
    validate_layout(asset_root, python_version)

    return asset_root


def main(argv: list[str]) -> int:
    out_root = Path(argv[1]).resolve() if len(argv) > 1 else DEFAULT_OUT_ROOT.resolve()
    built_path = build(out_root)
    log(f"done: {built_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
