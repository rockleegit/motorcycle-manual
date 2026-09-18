# 构建说明与进度（build/）

> 本文档替代原先被构建进程异常输出污染的旧版（乱码已清除）。

## 产物清单

| 文件 | 说明 |
|------|------|
| `merged.md` | 全部章节合并稿（vol01–vol06 + appendix；脚本自动插入文件分隔标记） |
| `manual.tex` | 由 merged.md 经 pandoc 转换、套用 `template.tex` |
| `摩托车维修全手册.pdf` | xelatex 成品 |
| `摩托车维修全手册.epub` | EPUB 成品 |
| `site.html` / `site_raw.html` / `摩托车维修全手册_网站.html` / `摩托车维修全手册_测试.html` | 网页版（含搜索注入） |
| `template.tex` | xelatex 模板（章节样式、字体设置） |

## 脚本

| 脚本 | 用途 |
|------|------|
| `build.sh` | 主流程：合并 markdown → tex → PDF → EPUB |
| `build-pdf-html.sh` | 生成网页版 HTML（内嵌 Python 注入 CSS 与搜索功能） |
| `gen_chapter_prompt.sh` | 生成分章写作/审校提示词 |

**用法**：在仓库根目录执行 `./build/build.sh`。

脚本通过 `BASH_SOURCE` 自动推导仓库根目录，可在任意位置调用；脚本内的绝对路径与平台相关配置已参数化（`build-pdf-html.sh` 的 Python 段通过 `BUILD_DIR` 环境变量接收构建目录）。

## 环境要求

- **pandoc**（原构建环境为 3.10）
- **xelatex** + 中文宏包（ctex、multirow、titlesec 等；原环境用 BasicTeX）
- **Python 3**（`build-pdf-html.sh` 用到）

## 已知问题

1. **中文字体识别**：xelatex 曾报 `The font "Hiragino Sans GB" cannot be found`。可选方案：
   - 用完整字体规格 `[Path=/path/to/font.ttc, BoldFont=..., ItalicFont=...]` 指定 `.ttc`；
   - 换用其他中文字体（如 STHeiti Medium）；
   - 安装 fontconfig，用 `fc-list` 让 xelatex 解析系统字体；
   - 绕开 xelatex——用浏览器直接打印为 PDF。
2. **产物与正文同步**：正文修订后必须重跑构建，否则 PDF/EPUB/HTML 会滞后于最新内容（历史上出现过产物带着已修错误的情况）。
3. `template.tex` 内的字体设置与平台相关，跨平台构建前需先调整。

## 构建历史

- 2026-09-17：随 A01 修订重打 PDF + HTML（未重打 EPUB）
- 2026-09-18：正文完成独立审校修复（P0 高危 12 处 + P1 确认错误约 60 处，见仓库根目录 `审校报告-2026-09-17.md`）——**当前 build/ 下产物尚未同步重打**
