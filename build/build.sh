#!/usr/bin/env bash
# 摩托车维修全手册 PDF 构建脚本
# 用法：在项目根目录 ~/motorcycle-manual 下跑 ./build/build.sh
# 先生改完章节后，再跑一次这条命令即可重打 PDF
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Windows(Git Bash) 下 pandoc / xelatex / python 都是原生程序，认不出 /c/... 形式，
# 这里统一转成 C:/... （cygpath -m 用正斜杠，Python 字符串里也能直接用）。
# macOS / Linux 没有 cygpath，保持原样即可。
if command -v cygpath >/dev/null 2>&1; then
  ROOT="$(cygpath -m "$ROOT")"
fi
BUILD="$ROOT/build"
SRC_VOL=("./vol01" "./vol02" "./vol03" "./vol04" "./vol05" "./vol06")
APPENDIX_DIR="./appendix"
MERGED="$BUILD/merged.md"
TEMPLATE="$BUILD/template.tex"
OUT_TEX="$BUILD/manual.tex"
OUT_PDF="$BUILD/摩托车维修全手册.pdf"

cd "$ROOT"

# ─────────────── 1. 合并 markdown ───────────────
# 顺序：vol01..vol06 → appendix；每个文件之间加水平分割 + 元信息注释，
# 这样 pandoc 能识别 chapter / section 分页点。
# 把文件内的独立 `---` 行替换为水平分割线注释
# （pandoc 默认把开头的 --- 当 YAML，会让 CH07 内部的 --- 触发解析错误）
# 使用 awk 一次性处理每个文件
process_file() {
  local f="$1"
  local is_first="$2"
  if [ "$is_first" -eq 1 ]; then
    printf '<!-- file: %s -->\n\n' "$f"
    # Mermaid 块改成 text(PDF 用 lstlisting 渲染,HTML 站点不受影响)
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
      # 跳过 AUDIT-LOG.md(项目维护文件,不是章节内容)
      # 注意:每章都有独立的审校日志,必须全量排除,否则会被当作章节并入成品
      case "$f" in
        *AUDIT-LOG*.md) continue ;;
      esac
      process_file "$f" "$first"
      first=0
    done
  done
  if [ -d "$APPENDIX_DIR" ]; then
    for f in "$APPENDIX_DIR"/*.md; do
      [ -f "$f" ] || continue
      # 附录同样要排除审校日志（A01-AUDIT-LOG.md 否则会被当成附录正文并入成品）
      case "$f" in
        *AUDIT-LOG*.md) continue ;;
      esac
      process_file "$f" "$first"
      first=0
    done
  fi
} > "$MERGED"

echo "✅ merged.md: $(wc -l < "$MERGED") 行, $(wc -c < "$MERGED") 字节"

# ─────────────── 2. pandoc 转 tex ───────────────
# 资源路径已设好，pandoc 在 merged.md 里相对路径找图；
# --toc 自动生成目录；--template 用我们的 xelatex 模板。
pandoc "$MERGED" \
  --from=markdown+yaml_metadata_block+raw_html+raw_tex+tex_math_dollars+tex_math_single_backslash+latex_macros \
  --to=latex \
  --template="$TEMPLATE" \
  --toc \
  --toc-depth=3 \
  --top-level-division=chapter \
  --resource-path="$ROOT" \
  --metadata=documentclass:"book" \
  --syntax-highlighting=none \
  -o "$OUT_TEX"
echo "✅ manual.tex: $(wc -l < "$OUT_TEX") 行"

# ─────────────── 3. xelatex 编译（跑两次让 toc/bookmarks 稳定） ───────────────
cd "$BUILD"
for pass in 1 2; do
  # 不加 -halt-on-error:有警告就警告,不全停
  xelatex -interaction=nonstopmode "$OUT_TEX" \
    > "$BUILD/xelatex-pass${pass}.log" 2>&1 \
    || true  # 即使 xelatex 退出码非 0 也不中断(警告可以放过)
done

# ─────────────── 4. 缺字检查（换字体/换平台后最容易踩的坑） ───────────────
# 《手册》正文含 ⭐ ❓ ✓ ✗ 等符号，常规中文字体多未收录；template.tex 里已用
# newunicodechar 回退到 Segoe UI Symbol。这里把漏网字符暴露出来，避免 PDF 里
# 出现空白而无人察觉。
if [ -f "$BUILD/xelatex-pass2.log" ]; then
  # 注意：grep 无匹配时返回 1，在本脚本的 set -e / pipefail 下会让整体中止，
  # 所以整条管道末尾必须兜一个 || true。
  MISSING="$(grep -a "Missing character" "$BUILD/xelatex-pass2.log" \
             | sed 's/.*Missing character: //' | sort -u || true)"
  if [ -n "$MISSING" ]; then
    echo ""
    echo "⚠️  发现缺字（PDF 中会显示为空白），需要补进 template.tex 的字体回退表："
    echo "$MISSING" | head -20
    echo ""
  else
    echo "✅ 无缺字检查通过"
  fi
fi

# ─────────────── 5. 清理中间文件 ───────────────
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

# ─────────────── 5. 输出 EPUB（手机阅读 + 全文搜索） ───────────────
EPUB_OUT="$BUILD/摩托车维修全手册.epub"
pandoc "$MERGED" \
  --from=markdown+yaml_metadata_block+raw_html+raw_tex+tex_math_dollars+tex_math_single_backslash+latex_macros \
  --to=epub3 \
  --toc --toc-depth=3 \
  --metadata=title:"摩托车维修全手册" \
  --metadata=author:"维修手册项目" \
  --metadata=lang:"zh-CN" \
  -o "$EPUB_OUT" 2>/dev/null
echo ""
echo "📘 EPUB 输出：$EPUB_OUT"
ls -lh "$EPUB_OUT"

# ─────────────── 6. 输出 HTML 静态站（带模糊搜索） ───────────────
SITE_HTML="$BUILD/摩托车维修全手册_网站.html"
pandoc "$MERGED" \
  --from=markdown+yaml_metadata_block+raw_html+raw_tex+tex_math_dollars+tex_math_single_backslash+latex_macros \
  --to=html5 \
  --standalone \
  --toc --toc-depth=3 \
  --section-divs \
  --metadata=title:"摩托车维修全手册" \
  --metadata=lang:"zh-CN" \
  -o "$BUILD/site_raw.html" 2>/dev/null

# 用 Python 注入搜索 UI 和样式
# Windows 的 python3 可能是 Store 占位符（--version 能过、跑脚本 exit 49）；
# 真跑一段代码探测，失败就换 python。
PYTHON_BIN="python3"
if ! python3 -c "pass" >/dev/null 2>&1; then
  PYTHON_BIN="python"
fi
"$PYTHON_BIN" -c "
from pathlib import Path
import re
src = Path('$BUILD/site_raw.html').read_text(encoding='utf-8')
toc_match = re.search(r'<nav id=\"TOC\"[^>]*>(.*?)</nav>', src, re.DOTALL)
toc_inner = toc_match.group(1) if toc_match else '<ul><li>无目录</li></ul>'

# CSS
css = '''
<style>
  * { box-sizing: border-box; }
  body { margin: 0; padding: 0; font-family: -apple-system, \"PingFang SC\", \"Hiragino Sans GB\", \"Microsoft YaHei\", sans-serif; line-height: 1.7; color: #222; background: #fafafa; }
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
  article.content blockquote { border-left: 4px solid #1a1a1a; padding: 4px 12px; margin: 12px 0; background: #f8f8f8; color: #555; }
  .target-highlight { background: #fff3a3; padding: 2px 0; animation: fadeOut 2s forwards; }
  @keyframes fadeOut { 0% { background: #fff3a3; } 100% { background: transparent; } }
  @media (max-width: 768px) {
    header.app-bar h1 { font-size: 14px; }
    header.app-bar button.menu-toggle { display: block; }
    main.layout { display: block; }
    aside.sidebar { position: fixed; top: 50px; left: -300px; width: 280px; height: calc(100vh - 50px); transition: left 0.2s; z-index: 98; box-shadow: 2px 0 8px rgba(0,0,0,.2); }
    aside.sidebar.open { left: 0; }
    article.content { padding: 16px; max-width: 100%; }
    #search-results { top: 50px; }
  }
</style>
'''

# JS
js = '''
<script src=\"https://cdn.jsdelivr.net/npm/fuse.js@6.6.2/dist/fuse.min.js\"></script>
<script>
(function() {
  var searchIndex = [];
  var currentChap = '';
  document.querySelectorAll('article.content h1, article.content h2, article.content h3').forEach(function(h, i) {
    if (!h.id) h.id = 'h_' + i;
    var text = h.textContent.replace(/\\\\s+/g, ' ').trim();
    searchIndex.push({ id: h.id, title: text, tag: h.tagName, chap: currentChap });
    if (h.tagName === 'H1' || h.tagName === 'H2') currentChap = text;
  });
  var fuse = new Fuse(searchIndex, { keys: ['title'], threshold: 0.4, distance: 100, includeScore: true, minMatchCharLength: 1 });
  var input = document.getElementById('search');
  var results = document.getElementById('search-results');
  input.addEventListener('input', function() {
    var q = input.value.trim();
    if (q.length === 0) { results.classList.remove('active'); return; }
    var matches = fuse.search(q, {limit: 30});
    if (matches.length === 0) {
      results.innerHTML = '<div class=\"no-result\">没有匹配项。试试其他关键词，比如「液压」「点火」「气门间隙」</div>';
      results.classList.add('active');
      return;
    }
    var html = matches.map(function(m) {
      var tagBadge = m.item.tag === 'H1' ? '卷' : (m.item.tag === 'H2' ? '章' : '节');
      var chap = m.item.chap !== m.item.title && m.item.tag !== 'H1' ? '<div class=\"meta\">' + escapeHtml(m.item.chap) + '</div>' : '';
      var hl = highlight(m.item.title, q);
      return '<div class=\"result\" data-id=\"' + m.item.id + '\"><h4>' + hl + '</h4>' + chap + '<div class=\"meta\">[' + tagBadge + '] 匹配度 ' + ((1 - m.score) * 100).toFixed(0) + '%</div></div>';
    }).join('');
    results.innerHTML = html;
    results.classList.add('active');
    results.querySelectorAll('.result').forEach(function(el) {
      el.addEventListener('click', function() {
        var id = el.getAttribute('data-id');
        var target = document.getElementById(id);
        if (target) {
          target.scrollIntoView({behavior: 'smooth', block: 'start'});
          target.classList.add('target-highlight');
          setTimeout(function() { target.classList.remove('target-highlight'); }, 2000);
        }
        results.classList.remove('active');
        input.value = '';
      });
    });
  });
  input.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') { results.classList.remove('active'); input.value = ''; input.blur(); }
  });
  document.addEventListener('click', function(e) {
    if (!results.contains(e.target) && e.target !== input) results.classList.remove('active');
  });
  var menuBtn = document.querySelector('.menu-toggle');
  var sidebar = document.querySelector('aside.sidebar');
  if (menuBtn) menuBtn.addEventListener('click', function() { sidebar.classList.toggle('open'); });
  function escapeHtml(s) { return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }
  function highlight(text, q) {
    var safe = escapeHtml(text);
    if (!q) return safe;
    var re = new RegExp('(' + q.replace(/[.*+?^\${}()|[\\\\]\\\\]/g, '\\\\\$&') + ')', 'gi');
    return safe.replace(re, '<mark>\$1</mark>');
  }
})();
</script>
'''

body_match = re.search(r'<body[^>]*>', src)
if body_match:
    src = src[:body_match.end()] + '\\n' + css + '\\n' + src[body_match.end():]
src = re.sub(r'<nav id=\"TOC\"[^>]*>.*?</nav>', '', src, count=1, flags=re.DOTALL)
app_bar = '<header class=\"app-bar\"><button class=\"menu-toggle\">☰</button><h1>🏍️ 摩托车维修全手册</h1><div class=\"search-wrap\"><span class=\"search-icon\">🔍</span><input type=\"search\" id=\"search\" placeholder=\"搜索：液压、点火、气门间隙、刹车油 DOT 4...\" autocomplete=\"off\"></div></header><div id=\"search-results\"></div><main class=\"layout\"><aside class=\"sidebar\"><h2>📑 目录</h2><details open><summary>全手册目录</summary>__TOC__</details></aside><article class=\"content\">'
app_bar = app_bar.replace('__TOC__', toc_inner)
src = re.sub(r'<body([^>]*)>', r'<body\1>\\n' + app_bar, src, count=1)
src = src.replace('</body>', '  </article>\\n</main>\\n' + js + '\\n</body>')
Path('$SITE_HTML').write_text(src, encoding='utf-8')
print('site.html size:', Path('$SITE_HTML').stat().st_size, 'bytes')
"
echo ""
echo "🌐 HTML 站点输出：$SITE_HTML"
ls -lh "$SITE_HTML"