#!/usr/bin/env bash
# 临时脚本:只打 PDF + HTML(不打 EPUB)
# 复用 build.sh 的合并 + Python 注入风格,跳过 EPUB 段
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
        *CH13-AUDIT-LOG.md) continue ;;
        *CH01-AUDIT-LOG.md|*CH02-AUDIT-LOG.md|*CH03-AUDIT-LOG.md|*CH04-AUDIT-LOG.md|*CH05-AUDIT-LOG.md) continue ;;
        *CH06-AUDIT-LOG.md|*CH07-AUDIT-LOG.md|*CH08-AUDIT-LOG.md|*CH09-AUDIT-LOG.md|*CH10-AUDIT-LOG.md) continue ;;
        *CH11-AUDIT-LOG.md|*CH12-AUDIT-LOG.md|*CH14-AUDIT-LOG.md|*CH15-AUDIT-LOG.md|*CH16-AUDIT-LOG.md) continue ;;
        *CH17-AUDIT-LOG.md|*CH18-AUDIT-LOG.md|*CH19-AUDIT-LOG.md|*CH20-AUDIT-LOG.md|*CH21-AUDIT-LOG.md) continue ;;
        *CH22-AUDIT-LOG.md|*CH23-AUDIT-LOG.md|*CH24-AUDIT-LOG.md|*CH25-AUDIT-LOG.md) continue ;;
        *A01-AUDIT-LOG.md) continue ;;
      esac
      process_file "$f" "$first"
      first=0
    done
  done
  if [ -d "$APPENDIX_DIR" ]; then
    for f in "$APPENDIX_DIR"/*.md; do
      [ -f "$f" ] || continue
      case "$f" in
        *A01-AUDIT-LOG.md) continue ;;
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

# 改名
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
  -o "$BUILD/site_raw.html" 2>/dev/null

# 用 Python 注入搜索 UI 和样式(与 build.sh 一致)
python3 << 'PYEOF'
from pathlib import Path
import re

build = Path('/Users/liyuanbin/motorcycle-manual/build')
src = (build / 'site_raw.html').read_text()
toc_match = re.search(r'<nav id="TOC"[^>]*>(.*?)</nav>', src, re.DOTALL)
toc_inner = toc_match.group(1) if toc_match else '<ul><li>无目录</li></ul>'

css = '''
<style>
  * { box-sizing: border-box; }
  body { margin: 0; padding: 0; font-family: -apple-system, "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", sans-serif; line-height: 1.7; color: #222; background: #fafafa; }
  header.app-bar { position: sticky; top: 0; z-index: 100; background: #1a1a1a; color: #fff; padding: 10px 16px; display: flex; align-items: center; gap: 12px; box-shadow: 0 2px 8px rgba(0,0,0,.15); }
  header.app-bar h1 { font-size: 16px; font-weight: 600; margin: 0; flex: 0 0 auto; }
  header.app-bar .search-wrap { flex: 1 1 auto; position: relative; }
  header.app-bar input#search { width: 100%; padding: 8px 12px 8px 36px; border: none; border-radius: 6px; font-size: 15px; background: #333; color: #fff; outline: none; }
  header.app-bar input#search::placeholder { color: #999; }
  header.app-bar .search-icon { position: absolute; left: 10px; top: 50%; transform: translateY(-50%); color: #999; pointer-events: none; }
  header.app-bar button.menu-toggle { display: none; background: none; border: none; color: #fff; font-size: 20px; cursor: pointer; padding: 4px 8px; }
  #search-results { position: fixed; top: 50px; left: 0; right: 0; max-height: 60vh; overflow-y: auto; background: #fff; border-bottom: 2px solid #1a1a1a; z-index: 99; display: none; box-shadow: 0 4px 12px rgba(0,0,0,.1); }
  #search-results.active { display: block; }
  #search-results .result { padding: 12px 16px; border-bottom: 1px solid #eee; cursor: pointer; }
  #search-results .result:hover { background: #f0f7ff; }
  #search-results .result h4 { margin: 0 0 4px 0; font-size: 15px; color: #1a1a1a; }
  #search-results .result .excerpt { font-size: 13px; color: #666; }
  #search-results .result .meta { font-size: 11px; color: #999; margin-top: 2px; }
  #search-results .no-result { padding: 20px; text-align: center; color: #999; }
  #search-results mark { background: #ffe066; color: #000; padding: 0 2px; }
  main.layout { display: flex; min-height: calc(100vh - 50px); }
  aside.sidebar { width: 280px; flex: 0 0 280px; background: #fff; border-right: 1px solid #e0e0e0; padding: 16px; overflow-y: auto; height: calc(100vh - 50px); position: sticky; top: 50px; }
  aside.sidebar h2 { font-size: 13px; font-weight: 600; color: #666; margin: 0 0 12px 0; }
  aside.sidebar ul { list-style: none; padding: 0; margin: 0; }
  aside.sidebar a { display: block; padding: 6px 10px; color: #333; text-decoration: none; font-size: 14px; border-radius: 4px; line-height: 1.4; }
  aside.sidebar a:hover { background: #f0f7ff; color: #1a1a1a; }
  aside.sidebar ul ul { margin-left: 16px; }
  aside.sidebar ul ul a { font-size: 13px; color: #666; }
  aside.sidebar details { margin-bottom: 8px; }
  aside.sidebar details summary { cursor: pointer; padding: 4px 0; font-weight: 600; font-size: 14px; color: #1a1a1a; }
  article.content { flex: 1 1 auto; padding: 24px 32px; max-width: 920px; margin: 0 auto; background: #fff; }
  article.content h1, article.content h2, article.content h3 { scroll-margin-top: 60px; }
  article.content h1 { font-size: 24px; margin: 24px 0 16px; }
  article.content h2 { font-size: 20px; margin: 24px 0 12px; border-bottom: 2px solid #1a1a1a; padding-bottom: 4px; }
  article.content h3 { font-size: 17px; margin: 20px 0 10px; color: #333; }
  article.content p { margin: 0 0 12px 0; }
  article.content code { background: #f4f4f4; padding: 2px 5px; border-radius: 3px; font-size: 90%; }
  article.content pre { background: #f4f4f4; padding: 12px; border-radius: 4px; overflow-x: auto; font-size: 13px; line-height: 1.5; }
  article.content table { border-collapse: collapse; margin: 12px 0; font-size: 13px; width: 100%; }
  article.content th, article.content td { border: 1px solid #ddd; padding: 6px 10px; text-align: left; }
  article.content th { background: #f4f4f4; }
  article.content blockquote { border-left: 4px solid #1a1a1a; margin: 12px 0; padding: 8px 16px; background: #f9f9f9; color: #555; }
  article.content hr { border: none; border-top: 1px solid #ddd; margin: 24px 0; }
  article.content img { max-width: 100%; height: auto; }
  @media (max-width: 800px) {
    aside.sidebar { position: fixed; left: -300px; top: 50px; height: calc(100vh - 50px); transition: left 0.3s; z-index: 50; }
    aside.sidebar.open { left: 0; }
    main.layout { flex-direction: column; }
    header.app-bar button.menu-toggle { display: block; }
    article.content { padding: 16px; }
  }
</style>
'''

fuse_js = '''
<script src="https://cdn.jsdelivr.net/npm/fuse.js@6.6.2"></script>
<script>
(function() {
  const articles = [];
  document.querySelectorAll('article.content section, article.content h1[id], article.content h2[id], article.content h3[id]').forEach(el => {
    const heading = el.id || el.textContent.split('\\n')[0].trim().substring(0, 80);
    if (!heading) return;
    const text = el.textContent.replace(/\\s+/g, ' ').trim();
    if (text.length < 30) return;
    articles.push({ id: heading, title: heading, body: text });
  });

  const fuse = new Fuse(articles, {
    keys: ['title', 'body'],
    threshold: 0.3,
    ignoreLocation: true,
    includeMatches: true,
    minMatchCharLength: 2
  });

  const input = document.getElementById('search');
  const results = document.getElementById('search-results');
  if (!input || !results) return;

  let debounce;
  input.addEventListener('input', function() {
    clearTimeout(debounce);
    const q = this.value.trim();
    debounce = setTimeout(() => {
      if (q.length < 2) { results.classList.remove('active'); results.innerHTML = ''; return; }
      const hits = fuse.search(q, { limit: 30 });
      if (hits.length === 0) {
        results.innerHTML = '<div class="no-result">无匹配结果</div>';
        results.classList.add('active');
        return;
      }
      results.innerHTML = hits.map(h => {
        const m = h.matches?.[0];
        let excerpt = h.item.body.substring(0, 200);
        if (m && m.indices && m.indices[0]) {
          const start = Math.max(0, m.indices[0][0] - 50);
          excerpt = h.item.body.substring(start, start + 250);
        }
        const highlighted = excerpt.replace(/</g, '&lt;');
        return `<div class="result" data-anchor="${h.item.id}">
          <h4>${h.item.title}</h4>
          <div class="excerpt">${highlighted}...</div>
        </div>`;
      }).join('');
      results.classList.add('active');

      results.querySelectorAll('.result').forEach(r => {
        r.addEventListener('click', () => {
          const anchor = r.dataset.anchor;
          const target = document.getElementById(anchor) || document.querySelector('[id*="' + anchor + '"]');
          if (target) { target.scrollIntoView({ behavior: 'smooth', block: 'start' }); }
          results.classList.remove('active');
        });
      });
    }, 200);
  });
})();
</script>
'''

# 替换 <head> 注入 CSS,</body> 注入 JS,sidebar 注入 TOC
out = src
out = re.sub(r'<style>.*?</style>', css, out, count=1, flags=re.DOTALL)
out = re.sub(r'</head>', css + '</head>', out, count=1)
out = re.sub(r'<nav id="TOC"[^>]*>.*?</nav>', f'<aside class="sidebar" id="sidebar"><nav id="TOC">{toc_inner}</nav></aside>', out, count=1, flags=re.DOTALL)
if 'sidebar' not in out:
    out = re.sub(r'(<main[^>]*>)', r'<aside class="sidebar" id="sidebar"><nav id="TOC">' + toc_inner + r'</nav></aside>\1', out, count=1)
# 加 header app-bar
if 'app-bar' not in out:
    header_html = '<header class="app-bar"><h1>摩托车维修全手册</h1><span class="search-icon">🔍</span><div class="search-wrap"><input id="search" type="text" placeholder="搜索章节、术语..." autocomplete="off"></div><button class="menu-toggle" onclick="document.getElementById(\'sidebar\').classList.toggle(\'open\')">☰</button></header><main class="layout"><article class="content">'
    out = re.sub(r'<body>', '<body>' + header_html, out, count=1)
    out = re.sub(r'</body>', '</article></main>' + fuse_js + '</body>', out, count=1)
# 确保 search-results div 存在
if 'id="search-results"' not in out:
    out = re.sub(r'</header>', '</header><div id="search-results"></div>', out, count=1)

(build / '摩托车维修全手册_网站.html').write_text(out)
print('✅ HTML 输出:', build / '摩托车维修全手册_网站.html')
PYEOF

echo "🎉 完成:PDF + HTML(未打 EPUB)"