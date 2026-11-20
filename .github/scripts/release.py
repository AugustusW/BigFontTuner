#!/usr/bin/env python3
"""發版：GitHub tag → GitHub Release（附 zip）＋CurseForge 上傳。

由 .github/workflows/release.yml 呼叫；只用標準庫。
重點：
- 所有驗證（版本格式、tag 與 toc 一致、CHANGELOG 段落、遊戲版本對應）做完才有任何副作用。
- 順序：draft Release（附 zip）→ 上傳 CurseForge → 在 Release 說明寫記號 → 轉正式。
- 重跑時看 Release 狀態決定從哪一步接續；記號在就不再上傳。
- 上傳不重試；結果不明（逾時、連線錯誤、5xx、回應讀不出 id）一律停下，請人到 CurseForge 確認。

用法：
  python3 release.py run [--name 插件名]          # 事件資訊從 GitHub Actions 環境變數讀
  python3 release.py game-versions [--grep 1.60]  # 列出 CurseForge 遊戲版本（需要 CF_API_TOKEN）
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Mapping


class ReleaseError(Exception):
    """發版失敗，原因明確，沒有不確定的外部狀態。"""


class UploadUncertain(ReleaseError):
    """CurseForge 上傳結果不明：檔案可能已經收下，不能直接重跑。"""


@dataclass(frozen=True)
class Event:
    tag: str
    dry_run: bool
    skip_curseforge: bool


VERSION_RE = re.compile(r"\d+\.\d+\.\d+(-(alpha|beta)\.?\d*)?")
MARKER = "CurseForge file:"
MARKER_RE = re.compile(r"^CurseForge file: *(\d+)[ \t]*$", re.MULTILINE)
# 上傳前先寫「上傳中」記號：上傳結果不明或寫 file id 失敗時，Re-run 看到它就停下，不會再傳一次
PENDING = "CurseForge upload: pending"
CF_LINE_PREFIXES = (MARKER, "CurseForge upload:")


def _bool_input(env: Mapping[str, str], key: str) -> bool:
    value = env.get(key, "")
    if value == "true":
        return True
    if value == "false":
        return False
    raise ReleaseError(f"{key} 必須是 true 或 false，收到 {value!r}")


def parse_event(env: Mapping[str, str]) -> Event:
    name = env.get("GITHUB_EVENT_NAME", "")
    if name == "push":
        tag = env.get("GITHUB_REF_NAME", "")
        if not tag:
            raise ReleaseError("push 事件沒有 GITHUB_REF_NAME")
        return Event(tag, False, False)
    if name == "workflow_dispatch":
        tag = env.get("INPUT_TAG", "")
        if not tag:
            raise ReleaseError("手動執行要填 tag")
        return Event(tag, _bool_input(env, "INPUT_DRY_RUN"), _bool_input(env, "INPUT_SKIP_CURSEFORGE"))
    raise ReleaseError(f"不支援的事件：{name!r}")


def parse_tag(tag: str) -> tuple[str, str]:
    """回傳（版本, releaseType）。只接受 v1.2.3、v1.2.3-beta1、v1.2.3-alpha.2 這類格式。"""
    if not tag.startswith("v") or not VERSION_RE.fullmatch(tag[1:]):
        raise ReleaseError(
            f"tag {tag!r} 格式不對：只接受 v<主>.<次>.<修>，可加 -alpha／-beta 後綴（例：v0.8.0、v0.8.0-beta1）"
        )
    version = tag[1:]
    if "-alpha" in version:
        return version, "alpha"
    if "-beta" in version:
        return version, "beta"
    return version, "release"


def plugin_name(cli_name: str | None, env: Mapping[str, str]) -> str:
    if cli_name:
        return cli_name
    repo = env.get("GITHUB_REPOSITORY", "")
    if "/" in repo:
        return repo.split("/", 1)[1]
    raise ReleaseError("不知道插件名稱：用 --name 指定，或在 GitHub Actions 內執行")


def read_tocs(repo: Path, name: str) -> list[Path]:
    paths = sorted(p for p in repo.glob(f"{name}*.toc") if p.name == f"{name}.toc" or p.name.startswith(f"{name}_"))
    if not paths:
        raise ReleaseError(f"{repo} 找不到 {name}.toc 或 {name}_*.toc")
    return paths


def _toc_lines(path: Path) -> list[str]:
    return path.read_text(encoding="utf-8-sig").splitlines()


def _toc_value(path: Path, key: str) -> str | None:
    prefix = f"## {key}:"
    for line in _toc_lines(path):
        if line.startswith(prefix):
            return line[len(prefix):].strip()
    return None


def toc_field(paths: list[Path], key: str) -> str:
    values = {}
    for p in paths:
        v = _toc_value(p, key)
        if not v:
            raise ReleaseError(f"{p.name} 沒有 ## {key}")
        values[p.name] = v
    if len(set(values.values())) != 1:
        raise ReleaseError(f"各 toc 的 ## {key} 不一致：{values}")
    return next(iter(values.values()))


def toc_interfaces(paths: list[Path]) -> list[int]:
    result: list[int] = []
    for p in paths:
        raw = _toc_value(p, "Interface")
        if not raw:
            raise ReleaseError(f"{p.name} 沒有 ## Interface")
        for part in raw.split(","):
            part = part.strip()
            if not part.isdigit():
                raise ReleaseError(f"{p.name} 的 ## Interface 有無法解析的值：{part!r}")
            n = int(part)
            if n not in result:
                result.append(n)
    return result


def interface_to_name(n: int) -> str:
    return f"{n // 10000}.{n // 100 % 100}.{n % 100}"


def changelog_section(text: str, version: str) -> str:
    heading = f"## {version}"
    lines = text.splitlines()
    try:
        start = next(i for i, line in enumerate(lines) if line.rstrip() == heading)
    except StopIteration:
        raise ReleaseError(f"CHANGELOG.md 找不到「{heading}」段落") from None
    body = []
    for line in lines[start + 1:]:
        if line.startswith("## "):
            break
        body.append(line.rstrip())
    section = "\n".join(body).strip()
    if not section:
        raise ReleaseError(f"CHANGELOG.md 的「{heading}」段落是空的")
    return section


def match_game_versions(names: list[str], catalog: list[dict]) -> list[int]:
    ids = []
    for name in names:
        hits = [v for v in catalog if v.get("name") == name]
        if not hits:
            raise ReleaseError(f"CurseForge 遊戲版本找不到 {name!r}（用 release.py game-versions --grep 查候選）")
        if len(hits) > 1:
            listed = ", ".join(f"id={v.get('id')} gameVersionTypeID={v.get('gameVersionTypeID')}" for v in hits)
            raise ReleaseError(f"CurseForge 遊戲版本 {name!r} 對到多筆，不猜：{listed}")
        ids.append(int(hits[0]["id"]))
    return ids


def find_marker(body: str) -> int | None:
    m = MARKER_RE.findall((body or "").replace("\r\n", "\n"))
    return int(m[-1]) if m else None


def _strip_cf_lines(body: str) -> str:
    kept = [line for line in (body or "").replace("\r\n", "\n").split("\n") if not line.startswith(CF_LINE_PREFIXES)]
    return "\n".join(kept).rstrip()


def _append(body: str, line: str) -> str:
    text = _strip_cf_lines(body)
    return f"{text}\n\n{line}" if text else line


def add_marker(body: str, file_id: int) -> str:
    return _append(body, f"{MARKER} {file_id}")


def add_pending(body: str, run_id: str) -> str:
    return _append(body, f"{PENDING} (run {run_id})")


def has_pending(body: str) -> bool:
    return any(line.startswith(PENDING) for line in (body or "").replace("\r\n", "\n").split("\n"))


def clear_pending(body: str) -> str:
    return _strip_cf_lines(body) if find_marker(body) is None else body


# ---- CurseForge ----

CF_HOST = "https://wow.curseforge.com"
UNCERTAIN_HINT = "結果不明，先到 CurseForge 專案 Files 頁確認；已上傳就用 skip_curseforge 重跑並手動補記號"


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """上傳不跟隨重新導向：urllib 會把 POST 轉成 GET，看起來成功其實沒傳。"""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def build_metadata(name: str, version: str, changelog: str, game_version_ids: list[int], release_type: str) -> dict:
    return {
        "changelog": changelog,
        "changelogType": "markdown",
        "displayName": f"{name} {version}",
        "gameVersions": list(game_version_ids),
        "releaseType": release_type,
    }


def _error_body(e: urllib.error.HTTPError) -> str:
    try:
        return e.read().decode("utf-8", "replace")[:500]
    except Exception:  # 讀不到回應內容不影響錯誤分類
        return ""


class CurseForge:
    def __init__(self, token: str, host: str = CF_HOST, opener=None, timeout: float = 120):
        self._token = token
        self._host = host.rstrip("/")
        self._open = opener or urllib.request.build_opener(_NoRedirect).open
        self._timeout = timeout

    def _request(self, path: str, data: bytes | None = None, content_type: str | None = None):
        req = urllib.request.Request(self._host + path, data=data, method="POST" if data is not None else "GET")
        req.add_header("X-Api-Token", self._token)
        if content_type:
            req.add_header("Content-Type", content_type)
        return req

    def game_versions(self) -> list[dict]:
        try:
            with self._open(self._request("/api/game/versions"), timeout=self._timeout) as resp:
                data = json.loads(resp.read())
        except urllib.error.HTTPError as e:
            raise ReleaseError(f"查 CurseForge 遊戲版本失敗：HTTP {e.code} {_error_body(e)}") from None
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            raise ReleaseError(f"查 CurseForge 遊戲版本失敗：{e}") from None
        except ValueError:
            raise ReleaseError("CurseForge 遊戲版本回應不是 JSON") from None
        if not isinstance(data, list):
            raise ReleaseError("CurseForge 遊戲版本回應格式不對（不是陣列）")
        return data

    def upload(self, project_id: int, zip_path: Path, metadata: dict) -> int:
        boundary = uuid.uuid4().hex
        body = b"".join([
            f"--{boundary}\r\n".encode(),
            b'Content-Disposition: form-data; name="metadata"\r\n',
            b"Content-Type: application/json\r\n\r\n",
            json.dumps(metadata, ensure_ascii=False).encode("utf-8"), b"\r\n",
            f"--{boundary}\r\n".encode(),
            f'Content-Disposition: form-data; name="file"; filename="{zip_path.name}"\r\n'.encode(),
            b"Content-Type: application/zip\r\n\r\n",
            zip_path.read_bytes(), b"\r\n",
            f"--{boundary}--\r\n".encode(),
        ])
        req = self._request(f"/api/projects/{project_id}/upload-file", body, f"multipart/form-data; boundary={boundary}")
        try:
            with self._open(req, timeout=self._timeout) as resp:
                raw = resp.read()
        except urllib.error.HTTPError as e:
            detail = _error_body(e)
            if e.code >= 500:
                raise UploadUncertain(f"CurseForge 上傳回 HTTP {e.code}：{UNCERTAIN_HINT}。{detail}") from None
            raise ReleaseError(f"CurseForge 拒絕上傳：HTTP {e.code} {detail}") from None
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            raise UploadUncertain(f"CurseForge 上傳連線失敗（{e}）：{UNCERTAIN_HINT}") from None
        try:
            file_id = json.loads(raw)["id"]
        except (ValueError, KeyError, TypeError):
            file_id = None
        if not isinstance(file_id, int) or isinstance(file_id, bool):
            raise UploadUncertain(f"CurseForge 上傳回應讀不出檔案 id：{UNCERTAIN_HINT}。回應：{raw[:200]!r}")
        return file_id


# ---- GitHub（全部走 gh api，以 release id 操作）----
# 2026-11-20 在拋棄式私有 repo 實測的行為：
# - `GET releases/tags/<tag>` 查不到 draft；列 releases 看得到，但剛建立的 draft 約 1–2 秒內可能還列不到。
# - 同一 tag 可以建立多個 draft。
# - 只改 body 的 PATCH 會把 draft 的 tag 拿掉（tag_name 變成 untagged-xxxx），所以每次 PATCH 都帶 tag_name。

class Gh:
    def __init__(self, repo: str, runner=subprocess.run):
        self._repo = repo
        self._runner = runner

    def _api(self, *args: str, binary: bool = False):
        cmd = ["gh", "api", *args]
        proc = self._runner(cmd, capture_output=True, text=not binary)
        if proc.returncode != 0:
            err = proc.stderr.decode("utf-8", "replace") if binary else proc.stderr
            raise ReleaseError(f"gh api {args[0] if args else ''} 失敗：{err.strip()[:500]}")
        return proc.stdout

    @staticmethod
    def _norm(r: dict) -> dict:
        return {"id": r["id"], "draft": bool(r.get("draft")), "body": r.get("body") or "",
                "assets": [{"id": a["id"], "name": a["name"]} for a in r.get("assets") or []]}

    def find(self, tag: str) -> dict | None:
        out = self._api("--paginate", f"repos/{self._repo}/releases", "--jq",
                        ".[] | {id, tag_name, name, draft, body, assets: [.assets[] | {id, name}]}")
        version = tag[1:] if tag.startswith("v") else tag
        hits = []
        for line in out.splitlines():
            if line.strip():
                r = json.loads(line)
                if r.get("tag_name") == tag:
                    hits.append(r)
                elif r.get("draft") and str(r.get("tag_name", "")).startswith("untagged-") and r.get("name") == version:
                    raise ReleaseError(
                        f"有一個標題 {version} 但 tag 已脫鉤（{r.get('tag_name')}）的 draft（id {r['id']}），"
                        f"可能是上次發版留下的。先到 GitHub 確認它有沒有「{MARKER}」記號，處理掉再重跑"
                    )
        if len(hits) > 1:
            raise ReleaseError(f"{tag} 有 {len(hits)} 個 Release（id {[h['id'] for h in hits]}），先到 GitHub 刪掉多餘的 draft")
        return self._norm(hits[0]) if hits else None

    def tag_exists(self, tag: str) -> bool:
        cmd = ["gh", "api", f"repos/{self._repo}/git/ref/tags/{tag}"]
        proc = self._runner(cmd, capture_output=True, text=True)
        if proc.returncode == 0:
            return True
        if "HTTP 404" in proc.stderr:
            return False
        raise ReleaseError(f"查 tag {tag} 失敗：{proc.stderr.strip()[:500]}")

    def create_draft(self, tag: str, title: str, body: str, prerelease: bool) -> dict:
        out = self._api("-X", "POST", f"repos/{self._repo}/releases", "-f", f"tag_name={tag}", "-f", f"name={title}",
                        "-f", f"body={body}", "-F", "draft=true", "-F", f"prerelease={'true' if prerelease else 'false'}")
        return self._norm(json.loads(out))

    def upload_asset(self, release: dict, path: Path) -> None:
        url = f"https://uploads.github.com/repos/{self._repo}/releases/{release['id']}/assets?name={path.name}"
        self._api("-X", "POST", "-H", "Content-Type: application/zip", url, "--input", str(path))

    def download_asset(self, asset_id: int, name: str, dest: Path) -> Path:
        data = self._api("-H", "Accept: application/octet-stream", f"repos/{self._repo}/releases/assets/{asset_id}",
                         binary=True)
        out = Path(dest) / name
        out.write_bytes(data)
        return out

    def set_body(self, release_id: int, tag: str, body: str) -> None:
        self._api("-X", "PATCH", f"repos/{self._repo}/releases/{release_id}", "-f", f"tag_name={tag}",
                  "-f", f"body={body}")

    def publish(self, release_id: int, tag: str) -> None:
        self._api("-X", "PATCH", f"repos/{self._repo}/releases/{release_id}", "-f", f"tag_name={tag}",
                  "-F", "draft=false")


# ---- 編排 ----

MARKER_RETRIES = 3


def run(event: Event, name: str, repo_dir: Path, gh, cf, package: Callable[[], Path], log=print) -> str:
    # 1. 驗證：全部做完才有副作用
    version, release_type = parse_tag(event.tag)
    tocs = read_tocs(repo_dir, name)
    toc_version = toc_field(tocs, "Version")
    if toc_version != version:
        raise ReleaseError(f"tag {event.tag} 與 toc 版本 {toc_version} 不一致")
    project_id = int(toc_field(tocs, "X-Curse-Project-ID"))
    changelog_path = repo_dir / "CHANGELOG.md"
    if not changelog_path.is_file():
        raise ReleaseError("找不到 CHANGELOG.md")
    notes = changelog_section(changelog_path.read_text(encoding="utf-8"), version)
    names = [interface_to_name(n) for n in toc_interfaces(tocs)]
    game_ids = match_game_versions(names, cf.game_versions())
    metadata = build_metadata(name, version, notes, game_ids, release_type)
    zip_name = f"{name}-{version}.zip"

    def packaged() -> Path:
        z = package()
        if z.name != zip_name:
            raise ReleaseError(f"打包產物是 {z.name}，預期 {zip_name}")
        return z

    if event.dry_run:
        z = packaged()
        log(f"dry-run：{zip_name} sha256 {hashlib.sha256(z.read_bytes()).hexdigest()}")
        log(f"dry-run：遊戲版本 {dict(zip(names, game_ids))}，Project ID {project_id}")
        log("dry-run：CurseForge metadata " + json.dumps(metadata, ensure_ascii=False))
        return "dry-run"

    # 2. 看 Release 狀態決定從哪一步接續
    if not gh.tag_exists(event.tag):
        raise ReleaseError(f"GitHub 上沒有 tag {event.tag}")
    rel = gh.find(event.tag)
    if rel and not rel["draft"]:
        log(f"{event.tag} 的 Release 已經是正式版，不再處理")
        return "already-published"
    if rel is None:
        rel = gh.create_draft(event.tag, version, notes, release_type != "release")
        log(f"已建立 draft Release（id {rel['id']}）")

    # zip 一律從目前的 commit 打包（可重現）；draft 上已有 zip 時必須逐 byte 相同，
    # 否則代表 tag 改打在別的 commit，舊 draft 不能沿用
    z = packaged()
    digest = hashlib.sha256(z.read_bytes()).hexdigest()
    log(f"{zip_name} sha256 {digest}")
    with tempfile.TemporaryDirectory() as tmp:
        asset = next((a for a in rel["assets"] if a["name"] == zip_name), None)
        if asset:
            old = gh.download_asset(asset["id"], zip_name, Path(tmp))
            old_digest = hashlib.sha256(old.read_bytes()).hexdigest()
            if old_digest != digest:
                raise ReleaseError(
                    f"draft 上的 {zip_name}（sha256 {old_digest}）與這次打包（sha256 {digest}）不同，"
                    f"可能是 tag 改打在別的 commit。先到 GitHub 刪掉這個 draft（id {rel['id']}）再重跑"
                )
            log(f"draft 上已有相同的 {zip_name}")
        else:
            gh.upload_asset(rel, z)
            log(f"已附上 {zip_name}")

        # 3. CurseForge：記號在就不再上傳；「上傳中」記號在就停下請人確認
        body = rel["body"]
        existing = find_marker(body)
        if existing is not None:
            log(f"Release 已記錄 CurseForge file {existing}，不再上傳")
        elif event.skip_curseforge:
            if has_pending(body):
                gh.set_body(rel["id"], event.tag, clear_pending(body))
            log("skip_curseforge：不上傳 CurseForge")
        elif has_pending(body):
            raise ReleaseError(
                "上次上傳 CurseForge 的結果不明（draft 說明有「上傳中」記號），不自動再傳。"
                "先到 CurseForge 專案 Files 頁確認：已收到就手動執行 workflow（dry_run=false、skip_curseforge=true）；"
                "沒收到就到 GitHub 刪掉 draft 說明裡「CurseForge upload: pending」那一行再重跑"
            )
        else:
            pending = add_pending(body, os.environ.get("GITHUB_RUN_ID", "local"))
            gh.set_body(rel["id"], event.tag, pending)
            try:
                file_id = cf.upload(project_id, z, metadata)
            except UploadUncertain:
                raise
            except ReleaseError:
                try:
                    gh.set_body(rel["id"], event.tag, clear_pending(pending))
                except ReleaseError as e:
                    log(f"清除「上傳中」記號失敗：{e}")
                raise
            log(f"CurseForge 上傳完成，file id {file_id}")
            body = add_marker(pending, file_id)
            last: Exception | None = None
            for _ in range(MARKER_RETRIES):
                try:
                    gh.set_body(rel["id"], event.tag, body)
                    break
                except ReleaseError as e:
                    last = e
            else:
                raise ReleaseError(
                    f"CurseForge 已上傳（file id {file_id}），但寫入 Release 記號失敗：{last}。"
                    f"到 GitHub 把 draft 說明最後的「{PENDING}…」那一行換成「{MARKER} {file_id}」再重跑，"
                    f"或手動執行 workflow（dry_run=false、skip_curseforge=true）"
                )

    # 4. 轉正式
    gh.publish(rel["id"], event.tag)
    log(f"{event.tag} 已發布")
    return "published"


# ---- CLI ----

def _default_package(repo_dir: Path, name: str, version_from_tag: Callable[[], str]) -> Callable[[], Path]:
    def package() -> Path:
        env = dict(os.environ, PKG_NAME=name)
        subprocess.run(["bash", "tools/package.sh"], cwd=repo_dir, env=env, check=True)
        return repo_dir / "dist" / f"{name}-{version_from_tag()}.zip"
    return package


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="GitHub tag → GitHub Release＋CurseForge")
    sub = parser.add_subparsers(dest="cmd", required=True)
    p_run = sub.add_parser("run")
    p_run.add_argument("--name")
    p_gv = sub.add_parser("game-versions")
    p_gv.add_argument("--grep", default="")
    args = parser.parse_args(argv)

    token = os.environ.get("CF_API_TOKEN", "")
    if not token:
        print("✗ 沒有 CF_API_TOKEN", file=sys.stderr)
        return 2
    cf = CurseForge(token)
    try:
        if args.cmd == "game-versions":
            for v in cf.game_versions():
                if args.grep in str(v.get("name", "")):
                    print(f"{v.get('name')}\tid={v.get('id')}\tgameVersionTypeID={v.get('gameVersionTypeID')}")
            return 0
        env = os.environ
        event = parse_event(env)
        name = plugin_name(args.name, env)
        repo_dir = Path.cwd()
        version = parse_tag(event.tag)[0]
        repo = env.get("GITHUB_REPOSITORY", "")
        if not repo and not event.dry_run:
            raise ReleaseError("沒有 GITHUB_REPOSITORY")
        result = run(event, name, repo_dir, Gh(repo), cf, _default_package(repo_dir, name, lambda: version))
        print(f"結果：{result}")
        return 0
    except UploadUncertain as e:
        print(f"✗ {e}", file=sys.stderr)
        return 3
    except (ReleaseError, subprocess.CalledProcessError) as e:
        print(f"✗ {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
