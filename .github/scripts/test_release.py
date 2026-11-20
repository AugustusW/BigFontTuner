"""release.py 的測試（標準庫 unittest；本機與 GitHub Actions 都用
`python3 -m unittest discover -s .github/scripts` 執行）。"""
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import release as R  # noqa: E402


def write(path: Path, text: str) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    return path


TOC = "## Interface: {iface}\n## Title: X\n## Version: {ver}\n## X-Curse-Project-ID: {pid}\nCore.lua\n"


class TempDirCase(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self._tmp.name)

    def tearDown(self):
        self._tmp.cleanup()


class ParseEventTest(unittest.TestCase):
    def test_parse_event(self):
        e = R.parse_event({"GITHUB_EVENT_NAME": "push", "GITHUB_REF_NAME": "v0.4.0"})
        self.assertEqual(e, R.Event("v0.4.0", False, False))
        e = R.parse_event({"GITHUB_EVENT_NAME": "workflow_dispatch", "INPUT_TAG": "v0.4.0",
                           "INPUT_DRY_RUN": "true", "INPUT_SKIP_CURSEFORGE": "false"})
        self.assertEqual(e, R.Event("v0.4.0", True, False))
        e = R.parse_event({"GITHUB_EVENT_NAME": "workflow_dispatch", "INPUT_TAG": "v0.4.0",
                           "INPUT_DRY_RUN": "false", "INPUT_SKIP_CURSEFORGE": "true"})
        self.assertEqual(e, R.Event("v0.4.0", False, True))
        with self.assertRaises(R.ReleaseError):
            R.parse_event({"GITHUB_EVENT_NAME": "workflow_dispatch", "INPUT_TAG": "v0.4.0",
                           "INPUT_DRY_RUN": "yes", "INPUT_SKIP_CURSEFORGE": "false"})
        with self.assertRaises(R.ReleaseError):
            R.parse_event({"GITHUB_EVENT_NAME": "pull_request", "GITHUB_REF_NAME": "v0.4.0"})
        with self.assertRaises(R.ReleaseError):
            R.parse_event({"GITHUB_EVENT_NAME": "workflow_dispatch", "INPUT_DRY_RUN": "true",
                           "INPUT_SKIP_CURSEFORGE": "false"})


class ParseTagTest(unittest.TestCase):
    def test_parse_tag(self):
        self.assertEqual(R.parse_tag("v0.4.0"), ("0.4.0", "release"))
        self.assertEqual(R.parse_tag("v0.5.0-beta1"), ("0.5.0-beta1", "beta"))
        self.assertEqual(R.parse_tag("v0.5.0-beta"), ("0.5.0-beta", "beta"))
        self.assertEqual(R.parse_tag("v0.5.0-alpha.2"), ("0.5.0-alpha.2", "alpha"))
        for bad in ("0.4.0", "v0.4.0-test1", "v0.4.0-hold", "v0.4.0-rc1", "v0.4", "v0.4.0 ", "v0.4.0-beta1x"):
            with self.subTest(bad=bad), self.assertRaises(R.ReleaseError):
                R.parse_tag(bad)


class PluginNameTest(unittest.TestCase):
    def test_plugin_name(self):
        self.assertEqual(R.plugin_name("Foo", {"GITHUB_REPOSITORY": "AugustusW/Bar"}), "Foo")
        self.assertEqual(R.plugin_name(None, {"GITHUB_REPOSITORY": "AugustusW/BigFontTuner"}), "BigFontTuner")
        with self.assertRaises(R.ReleaseError):
            R.plugin_name(None, {})


class TocTest(TempDirCase):
    def test_read_tocs_two_layouts(self):
        a = self.dir / "a"
        write(a / "BigFontTuner.toc", TOC.format(iface=16001, ver="0.7.0", pid=1))
        self.assertEqual([p.name for p in R.read_tocs(a, "BigFontTuner")], ["BigFontTuner.toc"])
        b = self.dir / "b"
        write(b / "SkillsItemsGuide_Mainline.toc", TOC.format(iface=120105, ver="0.4.0", pid=1))
        write(b / "SkillsItemsGuide_Forever.toc", TOC.format(iface=16001, ver="0.4.0", pid=1))
        self.assertEqual([p.name for p in R.read_tocs(b, "SkillsItemsGuide")],
                         ["SkillsItemsGuide_Forever.toc", "SkillsItemsGuide_Mainline.toc"])
        with self.assertRaises(R.ReleaseError):
            R.read_tocs(b, "Other")

    def test_toc_version_mismatch(self):
        x = write(self.dir / "X_Forever.toc", TOC.format(iface=16001, ver="0.4.0", pid=1))
        y = write(self.dir / "X_Mainline.toc", TOC.format(iface=120105, ver="0.4.1", pid=1))
        self.assertEqual(R.toc_field([x], "Version"), "0.4.0")
        with self.assertRaises(R.ReleaseError):
            R.toc_field([x, y], "Version")

    def test_project_id_must_agree(self):
        x = write(self.dir / "X_Forever.toc", TOC.format(iface=16001, ver="0.4.0", pid=1791116))
        y = write(self.dir / "X_Mainline.toc", TOC.format(iface=120105, ver="0.4.0", pid=1788540))
        z = write(self.dir / "X_Classic.toc", "## Interface: 11507\n## Version: 0.4.0\n")
        self.assertEqual(R.toc_field([x], "X-Curse-Project-ID"), "1791116")
        with self.assertRaises(R.ReleaseError):
            R.toc_field([x, y], "X-Curse-Project-ID")
        with self.assertRaises(R.ReleaseError):
            R.toc_field([x, z], "X-Curse-Project-ID")

    def test_toc_interfaces(self):
        x = write(self.dir / "X_Forever.toc", "## Interface: 16001, 120105\r\n## Version: 1.0.0\r\n")
        y = write(self.dir / "X_Mainline.toc", "## Interface: 120105\n## Version: 1.0.0\n")
        self.assertEqual(R.toc_interfaces([x, y]), [16001, 120105])


class InterfaceTest(unittest.TestCase):
    def test_interface_to_name(self):
        self.assertEqual(R.interface_to_name(16001), "1.60.1")
        self.assertEqual(R.interface_to_name(120105), "12.1.5")
        self.assertEqual(R.interface_to_name(11507), "1.15.7")


CHANGELOG = """# Changelog

## 0.4.0-beta1

- beta 內容

## 0.4.0

- 新增物品分頁

---

- New Items tab

## 0.3.0

- error log

## 0.2.0

"""


class ChangelogTest(unittest.TestCase):
    def test_changelog_exact_heading(self):
        self.assertEqual(R.changelog_section(CHANGELOG, "0.4.0"),
                         "- 新增物品分頁\n\n---\n\n- New Items tab")
        self.assertEqual(R.changelog_section(CHANGELOG, "0.4.0-beta1"), "- beta 內容")
        self.assertEqual(R.changelog_section(CHANGELOG.replace("\n", "\r\n"), "0.3.0"), "- error log")
        with self.assertRaises(R.ReleaseError):
            R.changelog_section(CHANGELOG, "0.5.0")
        with self.assertRaises(R.ReleaseError):
            R.changelog_section(CHANGELOG, "0.2.0")
        with self.assertRaises(R.ReleaseError):
            R.changelog_section(CHANGELOG, "0.4")


CATALOG = [
    {"id": 101, "gameVersionTypeID": 517, "name": "1.60.1", "slug": "1-60-1"},
    {"id": 102, "gameVersionTypeID": 517, "name": "12.1.5", "slug": "12-1-5"},
    {"id": 103, "gameVersionTypeID": 67408, "name": "1.15.7", "slug": "1-15-7"},
    {"id": 104, "gameVersionTypeID": 73246, "name": "1.15.7", "slug": "1-15-7-x"},
]


class GameVersionTest(unittest.TestCase):
    def test_match_game_versions(self):
        self.assertEqual(R.match_game_versions(["1.60.1", "12.1.5"], CATALOG), [101, 102])
        with self.assertRaises(R.ReleaseError) as cm:
            R.match_game_versions(["9.9.9"], CATALOG)
        self.assertIn("9.9.9", str(cm.exception))
        with self.assertRaises(R.ReleaseError) as cm:
            R.match_game_versions(["1.15.7"], CATALOG)
        self.assertIn("67408", str(cm.exception))
        self.assertIn("73246", str(cm.exception))


class MarkerTest(unittest.TestCase):
    def test_pending_marker(self):
        b = R.add_pending("notes", "123")
        self.assertTrue(R.has_pending(b))
        self.assertTrue(b.startswith("notes"))
        self.assertFalse(R.has_pending(R.clear_pending(b)))
        self.assertEqual(R.clear_pending(b), "notes")
        done = R.add_marker(b, 9)
        self.assertFalse(R.has_pending(done))
        self.assertEqual(R.find_marker(done), 9)
        self.assertTrue(R.has_pending("x\r\nCurseForge upload: pending (run 1)  \r\n"))

    def test_marker_roundtrip(self):
        self.assertEqual(R.find_marker(R.add_marker("x", 123)), 123)
        self.assertEqual(R.find_marker("x\r\nCurseForge file: 7  \r\n"), 7)
        self.assertIsNone(R.find_marker("x"))
        self.assertIsNone(R.find_marker(""))
        twice = R.add_marker(R.add_marker("x", 1), 2)
        self.assertEqual(twice.count("CurseForge file:"), 1)
        self.assertEqual(R.find_marker(twice), 2)


# ---- CurseForge client ----

import io  # noqa: E402
import json  # noqa: E402
import urllib.error  # noqa: E402
from email.parser import BytesParser  # noqa: E402
from email.policy import HTTP  # noqa: E402

TOKEN = "cf-test-token-0000"


class FakeResponse:
    def __init__(self, body: bytes, status: int = 200):
        self._body = body
        self.status = status

    def read(self):
        return self._body

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


class RecordingOpener:
    """記錄每次 Request；依序回傳設定好的結果（FakeResponse 或要丟的例外）。"""

    def __init__(self, *results):
        self.results = list(results)
        self.requests = []

    def __call__(self, req, timeout=None):
        self.requests.append(req)
        r = self.results.pop(0)
        if isinstance(r, BaseException):
            raise r
        return r


def http_error(code: int, body: str = "") -> urllib.error.HTTPError:
    return urllib.error.HTTPError("https://example.invalid", code, "x", {}, io.BytesIO(body.encode()))


class CurseForgeTest(TempDirCase):
    def setUp(self):
        super().setUp()
        self.zip = self.dir / "SkillsItemsGuide-0.4.0.zip"
        self.zip.write_bytes(b"PK\x03\x04fake-zip-bytes")
        self.meta = R.build_metadata("SkillsItemsGuide", "0.4.0", "- 內容", [101, 102], "release")

    def test_build_metadata(self):
        self.assertEqual(self.meta, {
            "changelog": "- 內容", "changelogType": "markdown", "displayName": "SkillsItemsGuide 0.4.0",
            "gameVersions": [101, 102], "releaseType": "release"})

    def test_upload_request_shape(self):
        opener = RecordingOpener(FakeResponse(b'{"id": 20402}'))
        cf = R.CurseForge(TOKEN, opener=opener)
        self.assertEqual(cf.upload(1791116, self.zip, self.meta), 20402)
        self.assertEqual(len(opener.requests), 1)
        req = opener.requests[0]
        self.assertEqual(req.get_method(), "POST")
        self.assertEqual(req.full_url, "https://wow.curseforge.com/api/projects/1791116/upload-file")
        self.assertEqual(req.get_header("X-api-token"), TOKEN)
        self.assertIsNone(req.get_header("User-agent"))
        raw = b"Content-Type: " + req.get_header("Content-type").encode() + b"\r\n\r\n" + req.data
        msg = BytesParser(policy=HTTP).parsebytes(raw)
        parts = {p.get_param("name", header="content-disposition"): p for p in msg.iter_parts()}
        self.assertEqual(set(parts), {"metadata", "file"})
        self.assertEqual(json.loads(parts["metadata"].get_payload(decode=True)), self.meta)
        self.assertEqual(parts["file"].get_filename(), "SkillsItemsGuide-0.4.0.zip")
        self.assertEqual(parts["file"].get_payload(decode=True), self.zip.read_bytes())

    def test_upload_uncertain_cases(self):
        cases = [TimeoutError("timed out"), urllib.error.URLError("reset"), http_error(503, "busy"),
                 FakeResponse(b"<html>ok</html>"), FakeResponse(b"{}"), FakeResponse(b'{"id": "x"}')]
        for r in cases:
            with self.subTest(r=r):
                cf = R.CurseForge(TOKEN, opener=RecordingOpener(r))
                with self.assertRaises(R.UploadUncertain) as cm:
                    cf.upload(1, self.zip, self.meta)
                self.assertIn("結果不明", str(cm.exception))

    def test_upload_redirect_and_4xx_are_release_error(self):
        for code, body in ((302, ""), (400, "bad gameVersions"), (403, "forbidden")):
            with self.subTest(code=code):
                cf = R.CurseForge(TOKEN, opener=RecordingOpener(http_error(code, body)))
                with self.assertRaises(R.ReleaseError) as cm:
                    cf.upload(1, self.zip, self.meta)
                self.assertNotIsInstance(cm.exception, R.UploadUncertain)
                self.assertIn(str(code), str(cm.exception))
                self.assertIn(body, str(cm.exception))
                self.assertNotIn(TOKEN, str(cm.exception))

    def test_upload_called_once(self):
        for r in (TimeoutError("t"), http_error(500), http_error(400)):
            opener = RecordingOpener(r, FakeResponse(b'{"id": 1}'))
            with self.assertRaises(R.ReleaseError):
                R.CurseForge(TOKEN, opener=opener).upload(1, self.zip, self.meta)
            self.assertEqual(len(opener.requests), 1)

    def test_game_versions(self):
        opener = RecordingOpener(FakeResponse(json.dumps(CATALOG).encode()))
        self.assertEqual(R.CurseForge(TOKEN, opener=opener).game_versions(), CATALOG)
        req = opener.requests[0]
        self.assertEqual(req.full_url, "https://wow.curseforge.com/api/game/versions")
        self.assertEqual(req.get_header("X-api-token"), TOKEN)
        for r in (http_error(403, "nope"), TimeoutError("t"), FakeResponse(b"<html>")):
            with self.subTest(r=r), self.assertRaises(R.ReleaseError):
                R.CurseForge(TOKEN, opener=RecordingOpener(r)).game_versions()

    def test_default_opener_does_not_follow_redirects(self):
        cf = R.CurseForge(TOKEN)
        handler = R._NoRedirect()
        self.assertIsNone(handler.redirect_request(None, None, 302, "Found", {}, "https://x"))
        self.assertTrue(callable(cf._open))


# ---- Gh（gh api 包裝）----

import hashlib  # noqa: E402
import subprocess  # noqa: E402


class FakeRunner:
    """取代 subprocess.run：記錄 argv，依序回傳設定好的 (returncode, stdout, stderr)。"""

    def __init__(self, *results):
        self.results = list(results)
        self.calls = []

    def __call__(self, args, **kwargs):
        self.calls.append(args)
        rc, out, err = self.results.pop(0)
        if not kwargs.get("text"):
            out = out if isinstance(out, bytes) else out.encode()
            err = err if isinstance(err, bytes) else err.encode()
        return subprocess.CompletedProcess(args, rc, out, err)


def rel_line(id_, tag, draft, body="", assets=(), name=None):
    return json.dumps({"id": id_, "tag_name": tag, "name": name or tag.lstrip("v"), "draft": draft, "body": body,
                       "assets": [{"id": a[0], "name": a[1]} for a in assets]})


class GhTest(TempDirCase):
    def test_gh_find_filters_by_tag_including_drafts(self):
        out = "\n".join([rel_line(1, "v0.3.0", False), rel_line(2, "v0.4.0", True, "b", [(9, "a.zip")])]) + "\n"
        runner = FakeRunner((0, out, ""))
        rel = R.Gh("AugustusW/X", runner=runner).find("v0.4.0")
        self.assertEqual(rel, {"id": 2, "draft": True, "body": "b", "assets": [{"id": 9, "name": "a.zip"}]})
        args = runner.calls[0]
        self.assertEqual(args[:3], ["gh", "api", "--paginate"])
        self.assertIn("repos/AugustusW/X/releases", args)
        self.assertIsNone(R.Gh("AugustusW/X", runner=FakeRunner((0, out, ""))).find("v9.9.9"))
        self.assertIsNone(R.Gh("AugustusW/X", runner=FakeRunner((0, "", ""))).find("v0.4.0"))

    def test_gh_find_duplicate_tag_errors(self):
        out = rel_line(1, "v0.4.0", True) + "\n" + rel_line(2, "v0.4.0", True) + "\n"
        with self.assertRaises(R.ReleaseError):
            R.Gh("AugustusW/X", runner=FakeRunner((0, out, ""))).find("v0.4.0")

    def test_gh_find_detects_untagged_draft(self):
        # 實測（2026-11-20 私有 repo）：只改 body 的 PATCH 會讓 draft 的 tag_name 變成 untagged-xxxx。
        # 這種 draft 用 tag 找不到，若當成「不存在」就會再建一個、再上傳一次，所以要擋下來請人處理。
        out = rel_line(3, "untagged-5e0760a105a039eb0494", True, name="0.4.0") + "\n"
        with self.assertRaises(R.ReleaseError) as cm:
            R.Gh("AugustusW/X", runner=FakeRunner((0, out, ""))).find("v0.4.0")
        self.assertIn("untagged", str(cm.exception))
        out = rel_line(3, "untagged-5e0760a105a039eb0494", True, name="0.3.0") + "\n"
        self.assertIsNone(R.Gh("AugustusW/X", runner=FakeRunner((0, out, ""))).find("v0.4.0"))

    def test_gh_error_is_not_none(self):
        with self.assertRaises(R.ReleaseError) as cm:
            R.Gh("AugustusW/X", runner=FakeRunner((1, "", "HTTP 401: Bad credentials"))).find("v0.4.0")
        self.assertIn("401", str(cm.exception))

    def test_gh_tag_exists_404_false(self):
        gh = R.Gh("AugustusW/X", runner=FakeRunner((0, '{"ref":"refs/tags/v0.4.0"}', "")))
        self.assertTrue(gh.tag_exists("v0.4.0"))
        self.assertIn("repos/AugustusW/X/git/ref/tags/v0.4.0", gh._runner.calls[0])
        gh = R.Gh("AugustusW/X", runner=FakeRunner((1, "", "gh: Not Found (HTTP 404)")))
        self.assertFalse(gh.tag_exists("v0.4.0"))
        with self.assertRaises(R.ReleaseError):
            R.Gh("AugustusW/X", runner=FakeRunner((1, "", "HTTP 500"))).tag_exists("v0.4.0")

    def test_gh_create_draft_argv(self):
        runner = FakeRunner((0, rel_line(5, "v0.5.0-beta1", True, "notes"), ""))
        rel = R.Gh("AugustusW/X", runner=runner).create_draft("v0.5.0-beta1", "0.5.0-beta1", "notes", True)
        self.assertEqual(rel["id"], 5)
        args = runner.calls[0]
        for want in ("-X", "POST", "repos/AugustusW/X/releases", "tag_name=v0.5.0-beta1", "name=0.5.0-beta1",
                     "body=notes", "draft=true", "prerelease=true"):
            self.assertIn(want, args)

    def test_gh_upload_asset_argv(self):
        z = self.dir / "X-0.4.0.zip"
        z.write_bytes(b"zip")
        runner = FakeRunner((0, "{}", ""))
        R.Gh("AugustusW/X", runner=runner).upload_asset({"id": 7}, z)
        args = runner.calls[0]
        self.assertIn("https://uploads.github.com/repos/AugustusW/X/releases/7/assets?name=X-0.4.0.zip", args)
        self.assertEqual(args[args.index("--input") + 1], str(z))
        self.assertIn("Content-Type: application/zip", args)

    def test_gh_download_set_body_publish_argv(self):
        runner = FakeRunner((0, b"zipbytes", ""), (0, "{}", ""), (0, "{}", ""))
        gh = R.Gh("AugustusW/X", runner=runner)
        out = gh.download_asset(9, "X-0.4.0.zip", self.dir)
        self.assertEqual(out.read_bytes(), b"zipbytes")
        self.assertIn("Accept: application/octet-stream", runner.calls[0])
        self.assertIn("repos/AugustusW/X/releases/assets/9", runner.calls[0])
        gh.set_body(7, "v0.4.0", "new body")
        self.assertIn("body=new body", runner.calls[1])
        self.assertIn("PATCH", runner.calls[1])
        # 實測：PATCH draft 不帶 tag_name 會把 tag 拿掉，所以每次 PATCH 都要帶
        self.assertIn("tag_name=v0.4.0", runner.calls[1])
        gh.publish(7, "v0.4.0")
        self.assertIn("draft=false", runner.calls[2])
        self.assertIn("tag_name=v0.4.0", runner.calls[2])
        self.assertIn("repos/AugustusW/X/releases/7", runner.calls[2])


# ---- run() 編排 ----

class FakeGh:
    """有狀態的 GitHub 替身。規則依 2026-11-20 在拋棄式私有 repo 實測的結果：
    - 列 releases 看得到 draft（tag_name 是原本的 tag）；但剛建立的 draft 約 1–2 秒內可能還列不到，
      所以 run 在同一次執行裡建立 draft 後一律用回傳的 id，不再 find。
    - 同一 tag 可以建立多個 draft（API 不擋），多筆時 find 報錯。
    - 只改 body 的 PATCH 會把 draft 的 tag 拿掉（變成 untagged-xxxx）；帶 tag_name 才保留。
      這裡用「set_body／publish 收到的 tag 與 release 不同就把 tag 改成 untagged」模擬。
    - create_draft 只在 tag 存在時成功。
    - 寫入方法可設定前幾次失敗。
    """

    def __init__(self, tags=("v0.4.0",)):
        self.tags = set(tags)
        self.releases = []  # dict: id, tag, draft, body, assets{name: bytes}
        self.calls = []
        self.fail = {}  # 方法名 → 剩餘失敗次數
        self.fail_marker_writes = 0  # 寫入含 CurseForge file 記號的 body 時失敗幾次

    def _maybe_fail(self, name):
        if self.fail.get(name, 0) > 0:
            self.fail[name] -= 1
            raise R.ReleaseError(f"{name} 失敗（模擬）")

    def _view(self, r):
        return {"id": r["id"], "draft": r["draft"], "body": r["body"],
                "assets": [{"id": hash((r["id"], n)) & 0xFFFF, "name": n} for n in r["assets"]]}

    def _get(self, rid):
        return next(r for r in self.releases if r["id"] == rid)

    def tag_exists(self, tag):
        self.calls.append("tag_exists")
        return tag in self.tags

    def find(self, tag):
        self.calls.append("find")
        hits = [r for r in self.releases if r["tag"] == tag]
        if len(hits) > 1:
            raise R.ReleaseError("重複")
        return self._view(hits[0]) if hits else None

    def create_draft(self, tag, title, body, prerelease):
        self.calls.append("create_draft")
        self._maybe_fail("create_draft")
        if tag not in self.tags:
            raise R.ReleaseError("tag 不存在")
        r = {"id": len(self.releases) + 1, "tag": tag, "title": title, "draft": True, "body": body,
             "prerelease": prerelease, "assets": {}}
        self.releases.append(r)
        return self._view(r)

    def upload_asset(self, release, path):
        self.calls.append("upload_asset")
        self._maybe_fail("upload_asset")
        self._get(release["id"])["assets"][path.name] = path.read_bytes()

    def download_asset(self, asset_id, name, dest):
        self.calls.append("download_asset")
        for r in self.releases:
            if name in r["assets"]:
                out = Path(dest) / name
                out.write_bytes(r["assets"][name])
                return out
        raise R.ReleaseError("asset 不存在")

    def _keep_tag(self, r, tag):
        if tag != r["tag"]:
            r["tag"] = "untagged-0000"

    def set_body(self, release_id, tag, body):
        self.calls.append("set_body")
        self._maybe_fail("set_body")
        if self.fail_marker_writes and R.find_marker(body) is not None:
            self.fail_marker_writes -= 1
            raise R.ReleaseError("set_body 失敗（模擬）")
        r = self._get(release_id)
        self._keep_tag(r, tag)
        r["body"] = body

    def publish(self, release_id, tag):
        self.calls.append("publish")
        self._maybe_fail("publish")
        r = self._get(release_id)
        self._keep_tag(r, tag)
        r["draft"] = False


class FakeCf:
    def __init__(self, catalog=CATALOG):
        self.catalog = catalog
        self.uploads = []  # (project_id, bytes, metadata)
        self.raise_on_upload = None
        self.next_id = 5000

    def game_versions(self):
        return self.catalog

    def upload(self, project_id, zip_path, metadata):
        if self.raise_on_upload:
            raise self.raise_on_upload
        self.uploads.append((project_id, zip_path.read_bytes(), metadata))
        self.next_id += 1
        return self.next_id


class RunTest(TempDirCase):
    def setUp(self):
        super().setUp()
        self.repo = self.dir / "repo"
        write(self.repo / "SkillsItemsGuide_Forever.toc", TOC.format(iface=16001, ver="0.4.0", pid=1791116))
        write(self.repo / "SkillsItemsGuide_Mainline.toc", TOC.format(iface=120105, ver="0.4.0", pid=1791116))
        write(self.repo / "CHANGELOG.md", CHANGELOG)
        self.gh = FakeGh()
        self.cf = FakeCf()
        self.packaged = 0
        self.logs = []

    def package(self):
        self.packaged += 1
        out = self.dir / "dist" / "SkillsItemsGuide-0.4.0.zip"
        out.parent.mkdir(exist_ok=True)
        out.write_bytes(b"zip-from-package")
        return out

    def run_(self, tag="v0.4.0", dry_run=False, skip=False):
        return R.run(R.Event(tag, dry_run, skip), "SkillsItemsGuide", self.repo, self.gh, self.cf,
                     self.package, log=self.logs.append)

    def rel(self):
        self.assertEqual(len(self.gh.releases), 1)
        return self.gh.releases[0]

    def test_happy_path(self):
        self.assertEqual(self.run_(), "published")
        r = self.rel()
        self.assertEqual(r["tag"], "v0.4.0")
        self.assertFalse(r["draft"])
        self.assertEqual(r["title"], "0.4.0")
        self.assertFalse(r["prerelease"])
        self.assertEqual(r["assets"], {"SkillsItemsGuide-0.4.0.zip": b"zip-from-package"})
        self.assertEqual(len(self.cf.uploads), 1)
        pid, data, meta = self.cf.uploads[0]
        self.assertEqual((pid, data), (1791116, b"zip-from-package"))
        self.assertEqual(meta, R.build_metadata("SkillsItemsGuide", "0.4.0",
                                                "- 新增物品分頁\n\n---\n\n- New Items tab", [101, 102], "release"))
        self.assertEqual(R.find_marker(r["body"]), 5001)
        self.assertTrue(r["body"].startswith("- 新增物品分頁"))
        self.assertTrue(any("5001" in line for line in self.logs))

    def test_beta_is_prerelease(self):
        for f in self.repo.glob("*.toc"):
            f.write_text(f.read_text().replace("0.4.0", "0.4.0-beta1"))
        self.gh.tags.add("v0.4.0-beta1")
        R.run(R.Event("v0.4.0-beta1", False, False), "SkillsItemsGuide", self.repo, self.gh, self.cf,
              lambda: self._pkg("SkillsItemsGuide-0.4.0-beta1.zip"), log=self.logs.append)
        self.assertTrue(self.rel()["prerelease"])
        self.assertEqual(self.cf.uploads[0][2]["releaseType"], "beta")

    def _pkg(self, name):
        out = self.dir / name
        out.write_bytes(b"z")
        return out

    def test_published_release_is_noop(self):
        self.run_()
        self.gh.calls.clear()
        self.assertEqual(self.run_(), "already-published")
        self.assertEqual(len(self.cf.uploads), 1)
        self.assertNotIn("set_body", self.gh.calls)
        self.assertNotIn("publish", self.gh.calls)

    def test_draft_with_marker_skips_upload(self):
        self.gh.fail["publish"] = 1
        with self.assertRaises(R.ReleaseError):
            self.run_()
        self.assertEqual(self.run_(), "published")
        self.assertEqual(len(self.cf.uploads), 1)

    def test_publish_failure_then_rerun(self):
        self.gh.fail["publish"] = 1
        with self.assertRaises(R.ReleaseError):
            self.run_()
        self.assertTrue(self.rel()["draft"])
        self.cf.uploads.clear()
        self.run_()
        self.assertEqual(self.cf.uploads, [])
        self.assertFalse(self.rel()["draft"])

    def test_draft_with_matching_asset_is_kept(self):
        self.cf.raise_on_upload = R.ReleaseError("HTTP 400")
        with self.assertRaises(R.ReleaseError):
            self.run_()
        self.cf.raise_on_upload = None
        self.gh.calls.clear()
        self.run_()
        self.assertNotIn("upload_asset", self.gh.calls)
        self.assertEqual(self.cf.uploads[0][1], b"zip-from-package")

    def test_draft_asset_from_other_commit_fails(self):
        # 第一次被 CurseForge 拒絕後，tag 改打在新 commit：draft 上的舊 zip 不能拿去上傳
        self.cf.raise_on_upload = R.ReleaseError("HTTP 400")
        with self.assertRaises(R.ReleaseError):
            self.run_()
        self.rel()["assets"]["SkillsItemsGuide-0.4.0.zip"] = b"zip-from-older-commit"
        self.cf.raise_on_upload = None
        with self.assertRaises(R.ReleaseError) as cm:
            self.run_()
        self.assertIn("sha256", str(cm.exception))
        self.assertEqual(self.cf.uploads, [])
        self.assertTrue(self.rel()["draft"])

    def test_draft_without_asset_repackages(self):
        self.gh.fail["upload_asset"] = 1
        with self.assertRaises(R.ReleaseError):
            self.run_()
        self.assertEqual(self.rel()["assets"], {})
        self.run_()
        self.assertEqual(self.rel()["assets"], {"SkillsItemsGuide-0.4.0.zip": b"zip-from-package"})
        self.assertEqual(len(self.cf.uploads), 1)
        self.assertEqual(len(self.gh.releases), 1)

    def test_upload_uncertain_leaves_draft_unpublished(self):
        self.cf.raise_on_upload = R.UploadUncertain("結果不明")
        with self.assertRaises(R.UploadUncertain):
            self.run_()
        r = self.rel()
        self.assertTrue(r["draft"])
        self.assertIsNone(R.find_marker(r["body"]))
        self.assertTrue(R.has_pending(r["body"]))
        self.assertNotIn("publish", self.gh.calls)

    def test_rerun_after_uncertain_upload_is_blocked(self):
        # 在同一份 GitHub 狀態上重跑（等於按 Actions 的 Re-run）：不能再傳一次
        self.cf.raise_on_upload = R.UploadUncertain("結果不明")
        with self.assertRaises(R.UploadUncertain):
            self.run_()
        self.cf.raise_on_upload = None
        with self.assertRaises(R.ReleaseError) as cm:
            self.run_()
        self.assertIn("skip_curseforge", str(cm.exception))
        self.assertEqual(self.cf.uploads, [])
        self.assertTrue(self.rel()["draft"])

    def test_rejected_upload_clears_pending(self):
        self.cf.raise_on_upload = R.ReleaseError("CurseForge 拒絕上傳：HTTP 400")
        with self.assertRaises(R.ReleaseError):
            self.run_()
        self.assertFalse(R.has_pending(self.rel()["body"]))
        self.cf.raise_on_upload = None
        self.assertEqual(self.run_(), "published")
        self.assertEqual(len(self.cf.uploads), 1)

    def test_pending_write_failure_stops_before_upload(self):
        self.gh.fail["set_body"] = 1
        with self.assertRaises(R.ReleaseError):
            self.run_()
        self.assertEqual(self.cf.uploads, [])

    def test_skip_curseforge_clears_pending_and_publishes(self):
        self.cf.raise_on_upload = R.UploadUncertain("結果不明")
        with self.assertRaises(R.UploadUncertain):
            self.run_()
        self.cf.raise_on_upload = None
        self.assertEqual(self.run_(skip=True), "published")
        r = self.rel()
        self.assertFalse(r["draft"])
        self.assertFalse(R.has_pending(r["body"]))
        self.assertEqual(self.cf.uploads, [])

    def test_marker_write_failure_reports_file_id(self):
        self.gh.fail_marker_writes = 3
        with self.assertRaises(R.ReleaseError) as cm:
            self.run_()
        self.assertIn("5001", str(cm.exception))
        self.assertIn("skip_curseforge", str(cm.exception))
        self.assertTrue(self.rel()["draft"])
        # 同一份狀態重跑（Re-run）：被擋下，不重複上傳
        with self.assertRaises(R.ReleaseError):
            self.run_()
        self.assertEqual(len(self.cf.uploads), 1)

    def test_marker_write_retry_succeeds(self):
        self.gh.fail_marker_writes = 2
        self.assertEqual(self.run_(), "published")
        self.assertEqual(R.find_marker(self.rel()["body"]), 5001)
        self.assertFalse(R.has_pending(self.rel()["body"]))
        self.assertEqual(len(self.cf.uploads), 1)

    def test_dry_run_no_side_effects(self):
        out = self.run_(dry_run=True)
        self.assertEqual(self.gh.calls, [])
        self.assertEqual(self.cf.uploads, [])
        text = "\n".join(self.logs)
        self.assertIn(hashlib.sha256(b"zip-from-package").hexdigest(), text)
        self.assertIn('"gameVersions": [101, 102]', text)
        self.assertEqual(out, "dry-run")

    def test_dry_run_on_already_published_tag_still_reports(self):
        self.run_()
        self.gh.calls.clear()
        self.logs.clear()
        self.assertEqual(self.run_(dry_run=True), "dry-run")
        self.assertEqual(self.gh.calls, [])
        self.assertTrue(any("sha256" in line for line in self.logs))

    def test_dry_run_does_not_need_tag(self):
        self.gh.tags.clear()
        self.assertEqual(self.run_(dry_run=True), "dry-run")

    def test_skip_curseforge(self):
        self.assertEqual(self.run_(skip=True), "published")
        self.assertEqual(self.cf.uploads, [])
        self.assertFalse(self.rel()["draft"])

    def test_validation_before_side_effects(self):
        cases = {
            "v0.4.1": None,  # tag 與 toc 版本不符
            "v0.4.0-rc1": None,  # 版號格式
        }
        for tag in cases:
            with self.subTest(tag=tag):
                self.gh = FakeGh(tags=(tag,))
                with self.assertRaises(R.ReleaseError):
                    self.run_(tag=tag)
                self.assertEqual(self.gh.calls, [])
        self.gh = FakeGh()
        self.cf = FakeCf(catalog=[])
        with self.assertRaises(R.ReleaseError):
            self.run_()
        self.assertEqual(self.gh.calls, [])
        (self.repo / "CHANGELOG.md").write_text("# Changelog\n")
        self.cf = FakeCf()
        with self.assertRaises(R.ReleaseError):
            self.run_()
        self.assertEqual(self.gh.calls, [])

    def test_missing_tag_fails_before_draft(self):
        self.gh.tags.clear()
        with self.assertRaises(R.ReleaseError):
            self.run_()
        self.assertEqual(self.gh.releases, [])
        self.assertEqual(self.cf.uploads, [])

    def test_package_name_must_match(self):
        with self.assertRaises(R.ReleaseError):
            R.run(R.Event("v0.4.0", False, False), "SkillsItemsGuide", self.repo, self.gh, self.cf,
                  lambda: self._pkg("Other-0.4.0.zip"), log=self.logs.append)
        self.assertEqual(self.cf.uploads, [])


if __name__ == "__main__":
    unittest.main()
