# 构建说明与进度（build/）

> 本文档替代原先被构建进程异常输出污染的旧版（乱码已清除）。
> 最近一次完整重打：**2026-09-23**（Windows + MiKTeX 25.12 / pandoc 3.11；含 2026-09-23 复核轮全部修复）。

## 产物清单

| 文件 | 说明 |
|------|------|
| `merged.md` | 全部章节合并稿（vol01–vol06 + appendix，共 27 个文件；脚本自动插入文件分隔标记） |
| `manual.tex` | 由 merged.md 经 pandoc 转换、套用 `template.tex` |
| `摩托车维修全手册.pdf` | xelatex 成品（A4 单栏，666+ 页，带目录与 PDF 书签） |
| `摩托车维修全手册.epub` | EPUB3 成品（手机阅读 + 全文搜索） |
| `摩托车维修全手册_网站.html` | 网页版（内嵌 CSS + fuse.js 模糊搜索 + 侧边目录） |
| `site_raw.html` | 网页版中间产物（pandoc 直出的 standalone HTML） |
| `template.tex` | xelatex 模板（章节样式、字体设置、字形回退表） |

已删除的两个历史产物：`site.html`、`摩托车维修全手册_测试.html`——均为早期命名方案下的残留，不被任何脚本生成，且内容滞后。如需找回：`git checkout 00ea63a -- build/site.html "build/摩托车维修全手册_测试.html"`。

## 脚本

| 脚本 | 用途 |
|------|------|
| `build.sh` | 主流程：合并 markdown → tex → PDF → EPUB → 网页版 HTML（含搜索注入） |
| `build-pdf-html.sh` | 早期流程：合并 → tex（带 `--listings`）→ PDF → 网页版 HTML |
| `gen_chapter_prompt.sh` | 生成分章写作/审校提示词 |

**用法**：在仓库根目录执行 `./build/build.sh`。

两个构建脚本的产物文件名一致，但风格略有差异：`build-pdf-html.sh` 传 `--listings`（代码块用 lstlisting），`build.sh` 不传（代码块用 verbatim，由 `template.tex` 用 fvextra 补上折行与边框）。目前 `build/` 下的产物由 `build.sh` 生成。

## 环境要求

- **pandoc** ≥ 3.9（本次用 3.9；Windows 上可用 `pip install pypandoc_binary` 获取自带二进制）
- **xelatex** + 中文宏包：`ctex`、`xeCJK`、`fontspec`、`siunitx`、`titlesec`、`tocloft`、`multirow`、`booktabs`、`tabularx`、`fancyhdr`、`xcolor`、`listings`、`longtable`、`newunicodechar`、`fvextra`、`amsmath`、`amssymb`
- **Python 3**（`build.sh` / `build-pdf-html.sh` 的 HTML 注入段）
- 中文字体：模板默认使用 Windows 自带字体（微软雅黑 / 黑体 / Times New Roman / Consolas / Segoe UI Symbol）

### Windows 构建注意事项（2026-09-18 实测）

1. **路径风格**：pandoc / xelatex / python 均为原生 Windows 程序，认不出 Git Bash 的 `/c/...` 形式。`build.sh` 已用 `cygpath -m` 把 `ROOT` 转成 `C:/...`；Python 段可直接使用，无需另外转换。
2. **字体**：`template.tex` 的字体族与文件名是平台相关的，换平台需同步替换（macOS 原用 Hiragino Sans GB / STHeiti）。
3. **字形回退**：正文含 ⭐ ❓ ✓ ✗ ⚠ ℃ ℉ ⊖ ⏚ ⊗ ◀ ▶ ━ ∝ ⊕ ⊙ ▭ ⏱ 🎯 等 21 个符号，微软雅黑 / 黑体 / Times / Consolas **均不收录**。模板已用 `newunicodechar` 把它们回退到 Segoe UI Symbol（该字体全覆盖），**只影响 PDF 渲染**，Markdown 源文件与 HTML / EPUB 保持原字符。新增符号时需一并补进该表。
4. **数学模式中的汉字**：正文有 `\(U_{端}=U_{oc}-I(R_{内}+R_{线}+R_{触点})\)` 这类中文下标公式，xeCJK 默认在数学模式不接管汉字，需 `\xeCJKsetup{CJKmath=true}`（模板已设）。
5. **模板里的美元符号**：`template.tex` 是 pandoc 模板，注释里也不能出现裸露的 `$`，否则 pandoc 会当成模板变量并报 `unexpected "$"`。
6. **代码块折行**：pandoc 不传 `--listings` 时输出 verbatim，默认不折行，本书长命令行会严重溢出页面（实测最大超宽 508pt）。模板用 fvextra 的 `Verbatim` 重定义了 `verbatim`，恢复折行并加上边框底色。

## 构建期自动检查

`build.sh` 在 xelatex 之后会扫 `xelatex-pass2.log` 里的 `Missing character` 并把漏网字符列出来。**换字体或换平台后务必看这一段**：缺字在 PDF 里表现为空白，肉眼容易漏。

## 已知问题

1. **章节/小节编号重复**：正文标题自带手工编号（`# 第2章 …`、`### 1.4.3 …`），LaTeX 又自动编号，导致目录里出现 `2.2.1 1.1.0 为什么分类很重要？` 这类双层编号。**旧版 PDF（646 页）同样存在**，非本次重打引入。若要消除，需在模板中关闭自动编号并调整 `\titleformat` 的编号域。
2. **产物与正文同步**：正文修订后必须重跑构建，否则 PDF/EPUB/HTML 会滞后于最新内容（历史上出现过产物带着已修错误对外分发的情况）。
3. **残留排版告警**：整本编译剩 3 处 `Overfull \hbox`（1.0pt / 7.3pt / 46.6pt，最后一处来自一个 longtable 的列宽），视觉影响很小。
4. **旧版 PDF 文本层不可用**：`00ea63a` 版 PDF 用 mac 字体（Hiragino Sans GB / STHeiti）编译，字体子集缺 ToUnicode 映射，文字无法正常复制/搜索。2026-09-18 重打后文本层正常。

## 构建历史

- 2026-09-17：随 A01 修订重打 PDF + HTML（未重打 EPUB）
- 2026-09-18（上午）：正文完成独立审校修复（P0 高危 12 处 + P1 确认错误约 60 处 + P2 系统性问题 + 速查表专项 100+ 处 + 覆盖度补充 25 项），见仓库根目录 `审校报告-2026-09-17.md`
- 2026-09-18（下午）：**全量重打产物**。构建期修复：
  - `build.sh` 附录循环漏过 AUDIT-LOG 过滤 → `A01-AUDIT-LOG.md` 混入成品
  - pandoc 参数缺 `tex_math_single_backslash` → 行内公式在 PDF 触发 `Missing $ inserted`、在 EPUB/HTML 被静默丢弃
  - 模板字体改为 Windows 字体，新增字形回退表与 `CJKmath`
  - 新增缺字自动检查；verbatim 代码块改 fvextra 折行（Overfull 由 33 处降至 3 处）
  - 清理两个不再生成的滞后 HTML 产物
