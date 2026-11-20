#!/bin/bash
# 打包 CurseForge 用的 zip：dist/BigFontTuner-<版本>.zip，zip 最外層是 BigFontTuner/ 資料夾。
# 內容與 export.sh 相同（toc 列出的檔案＋toc＋README），另外加上 LICENSE。
# 可重現：同一個 commit 打出來的 zip 逐 byte 相同（檔案時間統一用 SOURCE_DATE_EPOCH，
# 未設時取 HEAD 的 commit 時間；檔案依名稱排序後加入）。發版流程靠這點保證 GitHub 與 CurseForge 拿到同一個檔案。
# 目錄名不是插件名時（worktree、發布端 clone）用 PKG_NAME 指定。
set -euo pipefail
export TZ=UTC
cd "$(dirname "$0")/.."
NAME="${PKG_NAME:-$(basename "$(pwd)")}"
TOC="$NAME.toc"
VER=$(sed -n 's/^## Version: *//p' "$TOC" | tr -d '\r')
[ -n "$VER" ] || { echo "toc 沒有 Version" >&2; exit 1; }
if [ -n "$(git status --porcelain)" ]; then echo "工作目錄有未 commit 的修改，先 commit 再打包" >&2; exit 1; fi

files=("$TOC" README.md LICENSE)
while IFS= read -r line; do
  line="${line%$'\r'}"
  [[ -z "$line" || "$line" == \#* ]] && continue
  files+=("$line")
done < "$TOC"
# 圖示等資源（toc 的 IconTexture 會用到）不列在 toc 裡，整個 Media/ 一起帶
if [ -d Media ]; then while IFS= read -r m; do files+=("$m"); done < <(git ls-files Media); fi
# 字型不進 repo、不上架（使用者 2026-11-15：上架版不含字型，自用版另外打包）。
# FONTS_DIR 指到放 .ttf 與授權檔的資料夾時，一起放進 Fonts/，檔名加 -fonts。
FONTS_DIR="${FONTS_DIR:-}"

TMP=$(mktemp -d)
for f in "${files[@]}"; do
  [ -f "$f" ] || { echo "缺少檔案：$f" >&2; exit 1; }
  mkdir -p "$TMP/$NAME/$(dirname "$f")"
  cp "$f" "$TMP/$NAME/$f"
done
if [ -n "$FONTS_DIR" ]; then
  [ -d "$FONTS_DIR" ] || { echo "FONTS_DIR 不存在：$FONTS_DIR" >&2; exit 1; }
  mkdir -p "$TMP/$NAME/Fonts"
  cp "$FONTS_DIR"/*.ttf "$FONTS_DIR"/*.txt "$TMP/$NAME/Fonts/"
fi
EPOCH="${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct)}"
python3 - "$TMP" "$EPOCH" <<'PY'
import os, sys
root, epoch = sys.argv[1], int(sys.argv[2])
for d, dirs, files in os.walk(root):
    for n in dirs + files:
        os.utime(os.path.join(d, n), (epoch, epoch), follow_symlinks=False)
PY
mkdir -p dist
OUT="dist/$NAME-$VER${FONTS_DIR:+-fonts}.zip"
rm -f "$OUT"
(cd "$TMP" && find "$NAME" -print | LC_ALL=C sort | zip -qX -@ "$OLDPWD/$OUT")
rm -rf "$TMP"
echo "已打包 $OUT（commit $(git rev-parse --short HEAD)）"
unzip -l "$OUT"
