#!/usr/bin/env bash
# 临时脚本:只打 PDF + HTML(不打 EPUB)
# 用 Python 注入(修正 regex 双反斜杠问题)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build"
SRC_VOL=("$ROOT/vol01" "$ROOT/vol02" "$ROOT/vol03" "$ROOT/vol04" "$ROOT/vol05" "$ROOT/vol06")
APPENDIX_DIR="$ROOT/appendix"
MERGED="$BUILD/merged.md"
TEMPLATE="$BUILD/template.tex"
OUT_TEX="$BUILD/manual.tex"
OUT_PDF="$BUILD/摩托车维修全手册.pdf"
SITE_HTML="$BUILD/摩托车维修全手册_网站.html"

cd "$ROOT"

# ─────────────── 1. 合并 markdown ───────────────
process_file() {
  local f="$1"
  local is_first="$2"
  if [ "$is_first" -eq 1 ]; then
    printf '<!-- file: %s -->\n\n' "$f"
    sed -e 's/^---$/<!-- horizontal-rule -->/' \
        -e 's/^```mermaid$/```text/' "$f"
    printf '\n'
  else
    printf '\n\n<!-- separator -->\n\n<!-- file: %s -->\n\n' "$f"
    sed -e 's/^---$/<!-- horizontal-rule -->/' \
        -e 's/^```mermaid$/```text/' "$f"
    printf '\n'
  fi
}

{
  first=1
  for vol in "${SRC_VOL[@]}"; do
    [ -d "$vol" ] || continue
    for f in "$vol"/*.md; do
      [ -f "$f" ] || continue
      case "$f" in
        *-AUDIT-LOG.md) continue ;;
      esac
      process_file "$f" "$first"
      first=0
    done
  done
  if [ -d "$APPENDIX_DIR" ]; then
    for f in "$APPENDIX_DIR"/*.md; do
      [ -f "$f" ] || continue
      case "$f" in
        *-AUDIT-LOG.md) continue ;;
      esac
      process_file "$f" "$first"
      first=0
    done
  fi
} > "$MERGED"

echo "✅ 已合并 → $MERGED"

# ─────────────── 2. 生成 LaTeX ───────────────
pandoc "$MERGED" \
  --from=markdown+yaml_metadata_block+raw_html+raw_tex+tex_math_dollars+latex_macros \
  --to=latex \
  --template="$TEMPLATE" \
  --toc \
  --toc-depth=3 \
  --top-level-division=chapter \
  --listings \
  -V documentclass=book \
  -V papersize=a4 \
  -V fontsize=10pt \
  --pdf-engine=xelatex \
  -V mainfont="PingFang SC" \
  -V CJKmainfont="PingFang SC" \
  -V monofont="Menlo" \
  -V geometry:margin=2.5cm \
  -V geometry:top=2.5cm \
  -V geometry:bottom=2.5cm \
  -V linkcolor=black \
  -V urlcolor=black \
  --metadata=documentclass=book \
  -o "$OUT_TEX"

echo "✅ 已生成 LaTeX → $OUT_TEX"

# ─────────────── 3. xelatex 编译两次 ───────────────
cd "$BUILD"
for pass in 1 2; do
  xelatex -interaction=nonstopmode "$OUT_TEX" \
    > "$BUILD/xelatex-pass${pass}.log" 2>&1 \
    || true
done
cd "$ROOT"

if [ -f "$BUILD/manual.pdf" ]; then
  cp "$BUILD/manual.pdf" "$OUT_PDF"
  echo "📕 PDF 输出: $OUT_PDF"
  ls -lh "$OUT_PDF"
fi

# ─────────────── 4. HTML 单页(带 fuse.js 搜索 + CSS) ───────────────
SITE_RAW="$BUILD/site_raw.html"
pandoc "$MERGED" \
  --from=markdown+yaml_metadata_block+raw_html+raw_tex+tex_math_dollars+latex_macros \
  --to=html5 \
  --standalone \
  --toc --toc-depth=3 \
  --section-divs \
  --metadata=title:"摩托车维修全手册" \
  --metadata=lang:"zh-CN" \
  -o "$SITE_RAW" 2>/dev/null

# 用 Python 注入(避免 heredoc 转义陷阱:用文件 + r-string)
BUILD_DIR="$BUILD" python3 << 'PYEOF'
import os
import re
from pathlib import Path

# 构建目录：优先用环境变量 BUILD_DIR（脚本调用时导出），否则回退到当前工作目录
build = Path(os.environ.get('BUILD_DIR', '.')).resolve()
src = (build / 'site_raw.html').read_text()

# CSS(简版,只保留关键)
css = """
<style>
  body { margin: 0; padding: 0; font-family: -apple-system, "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", sans-serif; line-height: 1.7; color: #222; background: #fafafa; }
  header.app-bar { position: sticky; top: 0; z-index: 100; background: #1a1a1a; color: #fff; padding: 10px 16px; display: flex; align-items: center; gap: 12px; box-shadow: 0 2px 8px rgba(0,0,0,.15); }
  header.app-bar h1 { font-size: 16px; font-weight: 600; margin: 0; flex: 0 0 auto; }
  header.app-bar .search-wrap { flex: 1 1 auto; position: relative; }
  header.app-bar input#search { width: 100%; padding: 8px 12px 8px 36px; border: none; border-radius: 6px; font-size: 15px; background: #333; color: #fff; outline: none; }
  header.app-bar .search-icon { position: absolute; left: 10px; top: 50%; transform: translateY(-50%); color: #999; pointer-events: none; }
  #search-results { position: fixed; top: 50px; left: 0; right: 0; max-height: 60vh; overflow-y: auto; background: #fff; border-bottom: 2px solid #1a1a1a; z-index: 99; display: none; box-shadow: 0 4px 12px rgba(0,0,0,.1); }
  #search-results.active { display: block; }
  #search-results .result { padding: 12px 16px; border-bottom: 1px solid #eee; cursor: pointer; }
  #search-results .result:hover { background: #f0f7ff; }
  #search-results .result h4 { margin: 0 0 4px 0; font-size: 15px; color: #1a1a1a; }
  #search-results .result .excerpt { font-size: 13px; color: #666; }
  #search-results .no-result { padding: 20px; text-align: center; color: #999; }
  #search-results mark { background: #ffe066; color: #000; padding: 0 2px; }
  main.layout { display: flex; min-height: calc(100vh - 50px); }
  aside.sidebar { width: 280px; flex: 0 0 280px; background: #fff; border-right: 1px solid #e0e0e0; padding: 16px; overflow-y: auto; height: calc(100vh - 50px); position: sticky; top: 50px; }
  aside.sidebar ul { list-style: none; padding: 0; margin: 0; }
  aside.sidebar a { display: block; padding: 6px 10px; color: #333; text-decoration: none; font-size: 14px; }
  aside.sidebar a:hover { background: #f0f7ff; }
  article.content { flex: 1 1 auto; padding: 24px 32px; max-width: 920px; margin: 0 auto; background: #fff; }
  article.content h1, article.content h2, article.content h3 { scroll-margin-top: 60px; }
  article.content h1 { font-size: 24px; }
  article.content h2 { font-size: 20px; border-bottom: 2px solid #1a1a1a; padding-bottom: 4px; }
  article.content h3 { font-size: 17px; }
  article.content code { background: #f4f4f4; padding: 2px 5px; border-radius: 3px; font-size: 90%; }
  article.content pre { background: #f4f4f4; padding: 12px; border-radius: 4px; overflow-x: auto; font-size: 13px; }
  article.content table { border-collapse: collapse; margin: 12px 0; font-size: 13px; width: 100%; }
  article.content th, article.content td { border: 1px solid #ddd; padding: 6px 10px; text-align: left; }
  article.content th { background: #f4f4f4; }
</style>
"""

# Fuse.js + 搜索逻辑(用 raw 字符串避免转义)
fuse_js = r'''
<script src="https://cdn.jsdelivr.net/npm/fuse.js@6.6.2"></script>
<script>
(function() {
  var articles = [];
  var nodes = document.querySelectorAll('article.content section, article.content h1[id], article.content h2[id], article.content h3[id]');
  for (var i = 0; i < nodes.length; i++) {
    var el = nodes[i];
    var heading = el.id || el.textContent.split('\n')[0].trim().substring(0, 80);
    if (!heading) continue;
    var text = el.textContent.replace(/\s+/g, ' ').trim();
    if (text.length < 30) continue;
    articles.push({ id: heading, title: heading, body: text });
  }
  var fuse = new Fuse(articles, {
    keys: ['title', 'body'],
    threshold: 0.3,
    ignoreLocation: true,
    includeMatches: true,
    minMatchCharLength: 2
  });
  var input = document.getElementById('search');
  var results = document.getElementById('search-results');
  if (!input || !results) return;
  var debounce;
  input.addEventListener('input', function() {
    clearTimeout(debounce);
    var q = this.value.trim();
    debounce = setTimeout(function() {
      if (q.length < 2) { results.classList.remove('active'); results.innerHTML = ''; return; }
      var hits = fuse.search(q, { limit: 30 });
      if (hits.length === 0) {
        results.innerHTML = '<div class="no-result">无匹配结果</div>';
        results.classList.add('active');
        return;
      }
      results.innerHTML = hits.map(function(h) {
        var m = h.matches && h.matches[0];
        var start = (m && m.indices && m.indices[0]) ? Math.max(0, m.indices[0][0] - 50) : 0;
        var excerpt = h.item.body.substring(start, start + 250);
        return '<div class="result" data-anchor="' + h.item.id + '"><h4>' + h.item.title + '</h4><div class="excerpt">' + excerpt + '...</div></div>';
      }).join('');
      results.classList.add('active');
      var rs = results.querySelectorAll('.result');
      for (var j = 0; j < rs.length; j++) {
        rs[j].addEventListener('click', function() {
          var a = this.dataset.anchor;
          var t = document.getElementById(a);
          if (t) t.scrollIntoView({ behavior: 'smooth', block: 'start' });
          results.classList.remove('active');
        });
      }
    }, 200);
  });
})();
</script>
'''

# 注入
out = src

# 1. CSS 注入:替换整个 <style>...</style> 块
out = re.sub(
    r'<style[^>]*>.*?</style>',
    css,
    out,
    count=1,
    flags=re.DOTALL
)

# 2. 提取 TOC 内容
toc_match = re.search(r'<nav id="TOC"[^>]*>(.*?)</nav>', out, re.DOTALL)
toc_inner = toc_match.group(1) if toc_match else '<ul><li>无目录</li></ul>'

# 3. 替换 nav#TOC 为 aside.sidebar
out = re.sub(
    r'<nav id="TOC"[^>]*>.*?</nav>',
    '<aside class="sidebar" id="sidebar"><nav id="TOC">' + toc_inner + '</nav></aside>',
    out,
    count=1,
    flags=re.DOTALL
)

# 4. 加 header app-bar
if '<header class="app-bar"' not in out:
    header_html = '<header class="app-bar"><h1>摩托车维修全手册</h1><span class="search-icon">🔍</span><div class="search-wrap"><input id="search" type="text" placeholder="搜索章节、术语..." autocomplete="off"></div></header><div id="search-results"></div><main class="layout"><article class="content">'
    # 用 lambda 包装,避免 fuse_js 里的 \\s 等被 re.sub 当转义
    out = re.sub(r'<body>', lambda m: '<body>' + header_html, out, count=1)
    out = re.sub(r'</body>', lambda m: '</article></main>' + fuse_js + '</body>', out, count=1)

# 5. 确保 search-results div 存在
if 'id="search-results"' not in out:
    out = re.sub(r'</header>', '</header><div id="search-results"></div>', out, count=1)

(build / '摩托车维修全手册_网站.html').write_text(out)
print('✅ HTML 输出:', build / '摩托车维修全手册_网站.html')
PYEOF

echo "🎉 完成:PDF + HTML(未打 EPUB)"