# mhtml

CNB 云原生开发环境 ↔ GitHub 双向同步方案

## 一句话用法

```bash
export GITHUB_TOKEN=ghp_你的token
bash /workspace/github-sync.sh
```

运行一次即可，之后直接用：

```bash
push "更新代码"          # → GitHub (排除敏感文件)
push-cnb "更新代码"      # → CNB (包含所有文件)
```

## 原理

### git remote 是什么

`git remote` 就是远程仓库的**书签**，记录名字和 URL。

```
origin  -> https://github.com/Map9876/mhtml.git   (GitHub)
cnb     -> https://cnb.cool/kfc50/mhtml.git      (CNB)
```

- `git push` 不指定远程时，默认推到当前分支追踪的远程，即 `origin`
- `origin` 只是默认名字，脚本把它从 CNB 改成 GitHub
- CNB 保留为 `cnb` remote

### 双端差异推送

`.gitignore` 是全局的，无法对不同远程设置不同规则。解决方案：

1. **推 GitHub**：`.gitignore` 排除敏感文件 → add/commit/push
2. **推 CNB**：临时移除 `.gitignore` 排除规则 → add 所有文件(含敏感文件) → push → 恢复 `.gitignore`

| 远程 | backup_jsonl_final/ | .codebuddy/ | 项目文件 |
|------|---------------------|-------------|----------|
| GitHub | 不包含 | 不包含 | 包含 |
| CNB | 包含 | 包含 | 包含 |

## 脚本做了什么

运行 `bash /workspace/github-sync.sh` 一条命令自动完成：

1. 从 `GITHUB_TOKEN` 获取 GitHub 用户名
2. 从 `CNB_REPO_SLUG` 环境变量读取仓库名
3. 检查 GitHub 是否已有该仓库，没有则自动创建（公开）
4. 将 `origin` 切换到 GitHub（带 token 认证），原 CNB 保存为 `cnb`
5. 配置 `.gitignore` 排除敏感目录
6. 同步 GitHub 上的最新内容到本地
7. 备份 `~/.codebuddy/` 对话记录到 `/workspace/backup_jsonl_final/`
8. 安装 `push` 和 `push-cnb` 快捷命令到 `/usr/local/bin/`

## push-cnb 做了什么

1. 备份 `~/.codebuddy/` 对话记录到 `/workspace/backup_jsonl_final/`
2. 临时移除 `.gitignore` 中的排除规则
3. `git add .` 包含所有文件
4. commit + push 到 CNB
5. `git reset --soft` 回退 commit，把敏感文件从 git 历史中彻底移除
6. 恢复 `.gitignore` 排除规则

这样后续 `push` 推到 GitHub 时，git 历史中不会有敏感文件，两个命令可以随意交替使用。

## 快速备份对话记录并推到 CNB

```bash
push-cnb "备份对话记录"
```

一条命令完成：备份 `~/.codebuddy/` → 推到 CNB → 清理本地历史。

## .gitignore 排除规则

```gitignore
# === github-sync: 以下文件不推送到 GitHub ===
backup_jsonl_final/
.codebuddy/
# === github-sync end ===
```

推 CNB 时临时删除这段，推完后恢复。如需修改排除列表，编辑 `/workspace/github-sync.sh` 中的 `EXCLUDE_PATTERNS`。

## 环境变量

| 变量 | 必须 | 说明 |
|------|------|------|
| `GITHUB_TOKEN` | 是 | GitHub Personal Access Token |
| `GITHUB_REPO` | 否 | 仓库名，默认从 `CNB_REPO_SLUG` 提取 |
| `GITHUB_OWNER` | 否 | GitHub 用户名，默认从 token 自动获取 |
| `CNB_REPO_SLUG` | 自动 | CNB 仓库路径（环境变量自带，如 `kfc50/mhtml`） |

## GPG 签名

CNB 环境默认 `commit.gpgsign=true`，与 GitHub 不互通。`push`/`push-cnb` 已内置 `-c commit.gpgsign=false`，无需手动处理。

## 子项目推送

`/workspace/` 下的嵌套 git 仓库无法直接 add，需复制到 `/tmp/` 推送：

```bash
cp -r /workspace/子项目 /tmp/子项目
cd /tmp/子项目
git remote add origin https://token@github.com/用户/子项目.git
git push -u origin main
```

## Token 安全

- token 存在 git remote URL 中（`https://token@github.com/...`）
- 也可放在 `/workspace/github-token.txt`，加入 `.gitignore`
- token 仅仓库权限时，泄露风险限于该仓库读写
- 建议定期轮换 token

---

# DLsite 封面搜索工具

从 Komiflo 排行榜 HTML 中提取漫画标题，在 DLsite 搜索匹配作品并获取封面图片 URL。

## 工作原理

1. 从 `Komiflo-2025-manga-rank-toplist/` 的 HTML 文件中用正则提取漫画标题
2. 对每个标题，通过 CDN 代理依次搜索 DLsite 的 `maniax`（同人）和 `book`（漫画）分区
3. 用标题匹配度评分（exact > startswith > partial）选择最佳结果
4. 通过 AJAX API 获取匹配作品的封面图 URL

## 尝试过的方法

### 1. 直接访问 DLsite API（失败）
- DLsite 对直接请求有地区限制/反爬，从大陆 IP 无法直接访问
- 返回 403 或超时

### 2. 通过 CDN 代理访问（成功）
- 使用 `https://c.map987.dpdns.org` 作为反代
- 所有 API 请求格式：`{CDN}/https://www.dlsite.com/...`
- 搜索 API：`/maniax/api/=/product.json?keyword={keyword}` 和 `/book/api/=/product.json?keyword={keyword}`
- 作品详情 AJAX API：`/maniax/product/info/ajax?product_id={workno}`

### 3. 标题匹配策略
- 日文标题含全角符号（！？．），需要 normalize 后比较
- 优先 exact match，其次 startswith，最后 partial match
- 部分 Komiflo 标题带有「最終話」「前編」等后缀，搜索前已剥离

### 4. 封面图字段
AJAX API 返回的 JSON 中，封面图可能在以下字段：
- `work_image` — 最常见
- `image_main` — 备用
- `image_url` — 备用

返回的 URL 是协议相对路径（`//img.dlsite.jp/...`），代码中补全为 `https:`。

## 是否修改了获取 API 的代码

**是的，做了以下修改：**
- 最初尝试直接请求 DLsite，失败后改用 CDN 代理
- 最初只搜索 `maniax` 分区，后来加上 `book` 分区以覆盖更多漫画类型
- `get_cover()` 函数最初只查 `work_image` 字段，后来加了 `image_main` 和 `image_url` 的 fallback

## 已找到 vs 未找到

### 已找到（示例）
| 排名 | Komiflo 标题 | DLsite 匹配 | Work No | 封面 |
|------|-------------|-------------|---------|------|
| 需运行脚本获取实际数据 | - | - | - | - |

> 实际结果请运行 `python3 dlsite_search.py` 生成 JSON 输出。

### 未找到的原因（常见）
- Komiflo 标题是中文翻译，DLsite 用日文原名，搜索匹配失败
- 部分作品仅在特定分区（如 `pro` 游戏、`appx` 手游）有收录
- 标题含特殊字符或副标题导致搜索无结果
- CDN 代理偶尔超时

## DLsite 封面图片 URL 规则

### URL 路径结构

```
https://img.dlsite.jp/{类型}/images2/work/{分区}/{ID范围}/{产品ID}_img_{部分}.{格式}
```

### 类型
| 类型 | 说明 |
|------|------|
| `resize` | 缩略图（有尺寸后缀） |
| `modpub` | 原图/大图 |

### 分区
| 分区 | 说明 |
|------|------|
| `doujin` | 同人（RJ 开头） |
| `books` | 漫画/书籍（BJ 开头） |
| `professional` | 商业作品（VJ 开头） |

### 图片部分
| 部分 | 说明 |
|------|------|
| `img_main` | 主封面图 |
| `img_smp1` ~ `img_smpN` | 试看样本页 |
| `img_sam` | 缩略封面（旧格式） |

## 真实封面链接示例

### 缩略图 → 原图（来自 maxurl #1312）

**书籍 (BJ)：**
```
缩略图: https://img.dlsite.jp/resize/images2/work/books/BJ617000/BJ616372_img_main_240x240.jpg
原  图: https://img.dlsite.jp/modpub/images2/work/books/BJ617000/BJ616372_img_main.jpg
```

**同人 (RJ)：**
```
缩略图: https://img.dlsite.jp/resize/images2/work/doujin/RJ438000/RJ437590_img_smp4.webp
原  图: https://img.dlsite.jp/modpub/images2/work/doujin/RJ438000/RJ437590_img_smp4.jpg
```

### 从缩略图 URL 转换为原图 URL 的规则

```python
def get_original_url(thumb_url: str) -> str:
    """将 DLsite 缩略图 URL 转换为原图 URL。"""
    url = thumb_url
    # 1. resize → modpub（去掉缩略图 CDN）
    url = url.replace("/resize/", "/modpub/")
    # 2. 去掉尺寸后缀（如 _240x240, _100x100）
    url = re.sub(r'_\d+x\d+', '', url)
    # 3. webp → jpg（原图通常是 jpg）
    url = url.replace('.webp', '.jpg')
    # 4. img_sam → img_main（旧缩略图字段）
    url = url.replace('img_sam.jpg', 'img_main.jpg')
    return url
```

### tissue 项目的 PHP 实现

`tissue/app/MetadataResolver/DLsiteResolver.php` 中使用 OGP 元数据获取封面，然后替换：

```php
// OGP 返回的可能是 img_sam（小缩略图），替换为 img_main（原图）
$metadata->image = str_replace('img_sam.jpg', 'img_main.jpg', $metadata->image);
```

## 获取最大图片的方法

### 方法 1：AJAX API（当前脚本使用）
```python
# /maniax/product/info/ajax 返回的 work_image 字段
# 返回的是 //img.dlsite.jp/modpub/... 原图 URL
info.get("work_image")  # 已经是原图
```

### 方法 2：从缩略图 URL 转换（参考 maxurl #1312）
```python
# 如果拿到的是 resize 缩略图，按上述规则转换
original = thumb_url.replace("/resize/", "/modpub/")
original = re.sub(r'_\d+x\d+', '', original)
```

### 方法 3：dlsite-async 库
`dlsite-async` 库的 `Work` 数据类有 `work_image` 和 `sample_images` 字段：
- `work_image`：主封面（来自 AJAX API，已是原图 URL）
- `sample_images`：试看页列表（来自 HTML `data-src` 属性）

**注意：`dlsite-async` 没有专门的"获取最大分辨率"逻辑**，它直接使用 API 返回的 URL。API 返回的 `work_image` 通常是 `modpub` 原图路径。

## maxurl issue #1312 参考

[maxurl #1312](https://github.com/qsniyg/maxurl/issues/1312) 提到的 DLsite URL 规则：

| 类型 | 示例 |
|------|------|
| Thumbnail (240x240) | `https://img.dlsite.jp/resize/images2/work/books/BJ617000/BJ616372_img_main_240x240.jpg` |
| Original | `https://img.dlsite.jp/modpub/images2/work/books/BJ617000/BJ616372_img_main.jpg` |
| WebP sample | `https://img.dlsite.jp/modpub/images2/work/doujin/RJ438000/RJ437590_img_smp4.webp` |
| Original sample | `https://img.dlsite.jp/modpub/images2/work/doujin/RJ438000/RJ437590_img_smp4.jpg` |

**关键发现：`modpub` 路径下直接就是原图，不需要额外的尺寸参数。`resize` 路径是 CDN 缩放版本。**

## 运行

```bash
cd /workspace
python3 dlsite_search.py 2>stderr.log > results.json
```

输出为 JSON 数组，每项包含 `rank`, `title`, `matched_name`, `workno`, `cover`。

## 依赖

- Python 3.x（标准库即可，无第三方依赖）
- CDN 代理可访问（`https://c.map987.dpdns.org`）
- Komiflo HTML 文件在 `Komiflo-2025-manga-rank-toplist/` 目录下
