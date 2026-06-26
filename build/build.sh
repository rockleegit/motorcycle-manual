#!/usr/bin/env bash
# 摩托车维修全手册 PDF 构建脚本
# 用法：在项目根目录 ~/motorcycle-manual 下跑 ./build/build.sh
# 先生改完章节后，再跑一次这条命令即可重打 PDF
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build"
SRC_VOL=("$ROOT/vol01" "$ROOT/vol02" "$ROOT/vol03" "$ROOT/vol04" "$ROOT/vol05" "$ROOT/vol06")
APPENDIX_DIR="$ROOT/appendix"
MERGED="$BUILD/merged.md"
TEMPLATE="$BUILD/template.tex"
OUT_TEX="$BUILD/manual.tex"
OUT_PDF="$BUILD/摩托车维修全手册.pdf"

cd "$ROOT"

# ─────────────── 1. 合并 markdown ───────────────
# 顺序：vol01..vol06 → appendix；每个文件之间加水平分割 + 元信息注释，
# 这样 pandoc 能识别 chapter / section 分页点。
{
  for vol in "${SRC_VOL[@]}"; do
    [ -d "$vol" ] || continue
    for f in "$vol"/*.md; do
      [ -f "$f" ] || continue
      printf '\n\n---\n\n<!-- file: %s -->\n\n' "$f"
      cat "$f"
      printf '\n'
    done
  done
  if [ -d "$APPENDIX_DIR" ]; then
    for f in "$APPENDIX_DIR"/*.md; do
      [ -f "$f" ] || continue
      printf '\n\n---\n\n<!-- file: %s -->\n\n' "$f"
      cat "$f"
      printf '\n'
    done
  fi
} > "$MERGED"

echo "✅ merged.md: $(wc -l < "$MERGED") 行, $(wc -c < "$MERGED") 字节"

# ─────────────── 2. pandoc 转 tex ───────────────
# 资源路径已设好，pandoc 在 merged.md 里相对路径找图；
# --toc 自动生成目录；--template 用我们的 xelatex 模板。
pandoc "$MERGED" \
  --from=markdown+yaml_metadata_block+raw_html+raw_tex+tex_math_dollars+latex_macros \
  --to=latex \
  --template="$TEMPLATE" \
  --toc \
  --toc-depth=3 \
  --top-level-division=chapter \
  --resource-path="$ROOT" \
  --metadata=documentclass:"book" \
  -o "$OUT_TEX"

echo "✅ manual.tex: $(wc -l < "$OUT_TEX") 行"

# ─────────────── 3. xelatex 编译（跑两次让 toc/bookmarks 稳定） ───────────────
cd "$BUILD"
for pass in 1 2; do
  xelatex -interaction=nonstopmode -halt-on-error "$OUT_TEX" \
    > "$BUILD/xelatex-pass${pass}.log" 2>&1 \
    || { echo "❌ xelatex 第 ${pass} 次失败，tail of log:"; tail -40 "$BUILD/xelatex-pass${pass}.log"; exit 1; }
done

# ─────────────── 4. 清理中间文件 ───────────────
rm -f "$BUILD"/manual.aux "$BUILD"/manual.log "$BUILD"/manual.out "$BUILD"/manual.toc \
      "$BUILD"/xelatex-pass*.log

if [ -f "$BUILD/manual.pdf" ]; then
  mv "$BUILD/manual.pdf" "$OUT_PDF"
fi

echo ""
echo "📕 PDF 输出：$OUT_PDF"
ls -lh "$OUT_PDF"
echo ""
echo "页数：$(pdfinfo "$OUT_PDF" 2>/dev/null | awk '/^Pages/{print $2}')"