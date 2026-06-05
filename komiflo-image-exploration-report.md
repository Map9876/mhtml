# Komiflo 图片尺寸探索报告

## 概述

本报告记录了对 komiflo.com 网站图片 URL 模式的完整探索，旨在发现可获取的最大图片尺寸。探索包括 API 分析、JS 文件解析、以及多个变体的测试验证。

## 测试对象

- **漫画页面**: https://komiflo.com/comics/28672
- **封面图片 filename**: `contents/1d9ef3bb320e36fb8acdcc7b49f3525d3c0b5512.jpg`
- **原始图片尺寸**: 4299×6071 像素, 424,791 bytes (415KB)

---

## API 端点分析

### 基本信息

```
GET https://api.komiflo.com/content/id/<漫画ID>
```

### 响应结构

```json
{
  "content": {
    "cdn_public": "https://image.komiflo-cdn.com/resized",
    "cdn_thumbs": "https://t.komiflo.com",
    "named_imgs": {
      "cover": {
        "id": 0,
        "original": 424791,
        "width": 4299,
        "height": 6071,
        "ident": "cover",
        "data": null,
        "filename": "contents/1d9ef3bb320e36fb8acdcc7b49f3525d3c0b5512.jpg?exp=1780628195&sig=zSdo-PAmP_hfGhm4xl6lPwkLOloBB9ngraxw__HGzYw"
      }
    }
  }
}
```

### 字段说明

| 字段 | 说明 |
|-----|------|
| `cdn_public` | 主变体 CDN 域名，用于高分辨率图片 |
| `cdn_thumbs` | 缩略图 CDN 域名，用于缩略图和中等分辨率图片 |
| `named_imgs.cover.filename` | 图片文件名，包含签名参数 |
| `named_imgs.cover.original` | 原始图片文件大小 (bytes) |
| `named_imgs.cover.width` | 原始图片宽度 (像素) |
| `named_imgs.cover.height` | 原始图片高度 (像素) |

---

## CDN 认证机制

### CloudFront Signed Cookies

Komiflo 使用 AWS CloudFront Signed Cookies 进行 CDN 认证。访问 `image.komiflo-cdn.com` 需要以下 cookies:

| Cookie | 说明 |
|--------|------|
| `CloudFront-Key-Pair-Id` | CloudFront 密钥对 ID |
| `CloudFront-Policy` | Base64 编码的访问策略 |
| `CloudFront-Signature` | CloudFront 签名 |

### Policy 解码

```json
{
  "Statement": [{
    "Resource": "https://image.komiflo-cdn.com/*",
    "Condition": {
      "DateLessThan": {
        "AWS:EpochTime": 1780587103
      }
    }
  }]
}
```

- **Resource**: 允许访问 `image.komiflo-cdn.com` 下的所有资源
- **过期时间**: Unix timestamp `1780587103` (2026-06-04 23:31:43)

### 获取 Cookies

Cookies 通过 API 端点获取:
```
GET https://api.komiflo.com/session/user
```

需要登录状态 (带 `sid` cookie)。

---

## JS 文件分析

### 文件信息

- **文件**: `komiflo.com/app-1b550038f844d360ca3c.js`
- **大小**: 1,707,084 bytes (1.7MB)
- **类型**: Webpack 打包的前端应用代码

### 变体数组定义

JS 文件中定义了两个变体数组，用于不同场景的图片加载:

#### 数组 r (主变体)

用于漫画阅读页面等需要高分辨率的场景，使用 `cdn_public` 域名。

```javascript
const r = [
  "2500_desktop_large_2x",   // 桌面端大尺寸 2x (最大)
  "1250_desktop_large",       // 桌面端大尺寸
  "625_desktop_large_half",   // 桌面端大尺寸 50%
  "2000_desktop_medium_2x",   // 桌面端中等 2x
  "1000_desktop_medium",      // 桌面端中等
  "500_desktop_medium_half",  // 桌面端中等 50%
  "1500_desktop_small_2x",    // 桌面端小尺寸 2x
  "1242_mobile_large_3x",     // 移动端大尺寸 3x
  "828_mobile_large_2x",      // 移动端大尺寸 2x
  "414_mobile_large",         // 移动端大尺寸
  "750_mobile_medium_2x",     // 移动端中等 2x
  "375_mobile_medium",        // 移动端中等
  "640_mobile_small_2x",      // 移动端小尺寸 2x
  "320_mobile_small"          // 移动端小尺寸
];
```

#### 数组 i (缩略图变体)

用于列表页、搜索结果等需要快速加载的场景，使用 `cdn_thumbs` 域名。

```javascript
const i = [
  "148_desktop_small",        // 桌面端小尺寸
  "296_desktop_small_2x",     // 桌面端小尺寸 2x
  "198_desktop_medium",       // 桌面端中等
  "396_desktop_medium_2x",    // 桌面端中等 2x
  "247_desktop_large",        // 桌面端大尺寸
  "494_desktop_large_2x",     // 桌面端大尺寸 2x
  "160_mobile_narrow",        // 移动端窄屏
  "320_mobile_narrow_2x",     // 移动端窄屏 2x
  "207_mobile_medium",        // 移动端中等
  "414_mobile_medium_2x",     // 移动端中等 2x
  "188_mobile_large",         // 移动端大尺寸
  "376_mobile_large_2x",      // 移动端大尺寸 2x
  "564_mobile_large_3x",      // 移动端大尺寸 3x (最大)
  "346_mobile"                // 移动端标准
];
```

### CDN 域名配置

```javascript
// 从 API 响应中获取
var cdn_public = content.cdn_public;  // "https://image.komiflo-cdn.com/resized"
var cdn_thumbs = content.cdn_thumbs;  // "https://t.komiflo.com"

// Staging 环境域名
var staging_cdn = "https://staging.t.komiflo.com";
```

### URL 构造逻辑

```javascript
// 图片 URL 构造
function buildImageUrl(cdnDomain, variant, filename) {
  return cdnDomain + "/" + variant + "/" + filename;
}

// 使用示例
var imageUrl = (cdn_thumbs || cdn_public) + "/" + variant + "/" + filename;
```

---

## 测试结果

### 无认证访问 (t.komiflo.com)

缩略图变体无需认证即可访问:

| 变体 | 文件大小 | 状态 |
|-----|---------|------|
| `148_desktop_small` | 20,962 bytes (20KB) | ✓ |
| `160_mobile_narrow` | 24,474 bytes (24KB) | ✓ |
| `188_mobile_large` | 32,555 bytes (32KB) | ✓ |
| `198_desktop_medium` | 35,590 bytes (35KB) | ✓ |
| `207_mobile_medium` | 38,855 bytes (38KB) | ✓ |
| `247_desktop_large` | 54,299 bytes (53KB) | ✓ |
| `296_desktop_small_2x` | 75,638 bytes (74KB) | ✓ |
| `320_mobile_narrow_2x` | 87,861 bytes (86KB) | ✓ |
| `346_mobile` | 101,161 bytes (99KB) | ✓ |
| `376_mobile_large_2x` | 119,217 bytes (116KB) | ✓ |
| `396_desktop_medium_2x` | 131,206 bytes (128KB) | ✓ |
| `414_mobile_medium_2x` | 142,019 bytes (139KB) | ✓ |
| `494_desktop_large_2x` | 200,448 bytes (196KB) | ✓ |
| **`564_mobile_large_3x`** | **263,915 bytes (258KB)** | **✓ (最大)** |

### 有认证访问 (image.komiflo-cdn.com + CloudFront cookies)

#### 缩略图变体 - 全部可用

| 变体 | 状态 |
|-----|------|
| 所有 14 个缩略图变体 | ✓ 200 |

#### 主变体 - 全部不存在

| 变体 | 状态 | 响应内容 |
|-----|------|---------|
| `2500_desktop_large_2x` | ✗ | "Not Found" (9 bytes) |
| `2000_desktop_medium_2x` | ✗ | "Not Found" (9 bytes) |
| `1500_desktop_small_2x` | ✗ | "Not Found" (9 bytes) |
| `1250_desktop_large` | ✗ | "Not Found" (9 bytes) |
| `1242_mobile_large_3x` | ✗ | "Not Found" (9 bytes) |
| `1000_desktop_medium` | ✗ | "Not Found" (9 bytes) |
| `828_mobile_large_2x` | ✗ | "Not Found" (9 bytes) |
| `640_mobile_small_2x` | ✗ | "Not Found" (9 bytes) |
| `625_desktop_large_half` | ✗ | "Not Found" (9 bytes) |
| `500_desktop_medium_half` | ✗ | "Not Found" (9 bytes) |
| `414_mobile_large` | ✗ | "Not Found" (9 bytes) |
| `375_mobile_medium` | ✗ | "Not Found" (9 bytes) |
| `320_mobile_small` | ✗ | "Not Found" (9 bytes) |

---

## 结论

### 最大可用图片

**`564_mobile_large_3x`** 是目前已知可获取的最大图片尺寸，文件大小约 258KB。

### 为什么更大的变体不可用

JS 文件中定义了更大的变体 (如 `2500_desktop_large_2x`)，但这些变体:

1. **在 CDN 上不存在**: 即使使用 CloudFront Signed Cookies 认证，仍然返回 "Not Found"
2. **可能是历史遗留**: 这些变体可能曾经存在但已被移除
3. **可能是预留配置**: 为未来功能预留的变体配置，但尚未生成实际图片

### 访问方式

#### 方式 1: 无认证 (推荐)

```
https://t.komiflo.com/{变体}/{filename}?exp={过期时间}&sig={签名}
```

- 无需认证
- 支持所有缩略图变体
- 最大: `564_mobile_large_3x` (258KB)

#### 方式 2: 有认证

```
https://image.komiflo-cdn.com/resized/{变体}/{filename}?exp={过期时间}&sig={签名}
```

- 需要 CloudFront Signed Cookies
- 同样只支持缩略图变体
- 主变体不存在

### 推荐使用方式

```bash
# 1. 获取 filename
curl -s "https://api.komiflo.com/content/id/<漫画ID>" | jq -r '.content.named_imgs.cover.filename'

# 2. 构造图片 URL (无需认证)
https://t.komiflo.com/564_mobile_large_3x/{filename}
```

---

## 变体命名规则

### 格式

```
{宽度}_{设备类型}_{尺寸类别}[_{倍率}]
```

### 设备类型

| 类型 | 说明 |
|-----|------|
| `desktop` | 桌面端 |
| `mobile` | 移动端 |

### 尺寸类别

| 类别 | 说明 |
|-----|------|
| `small` | 小尺寸 |
| `narrow` | 窄屏 |
| `medium` | 中等尺寸 |
| `large` | 大尺寸 |

### 倍率

| 倍率 | 说明 |
|-----|------|
| (无) | 1x 标准分辨率 |
| `2x` | 2x Retina 分辨率 |
| `3x` | 3x 高分辨率 |

### 宽度

数字表示图片的宽度 (像素)，例如:
- `564` → 564px 宽
- `1242` → 1242px 宽
- `2500` → 2500px 宽

---

## 相关项目参考

### 1. tissue (shikorism/tissue)

**仓库**: https://github.com/shikorism/tissue.git
**文件**: `app/MetadataResolver/KomifloResolver.php`

使用 `564_mobile_large_3x` 作为最大可用尺寸:

```php
$metadata->image = 'https://t.komiflo.com/564_mobile_large_3x/' . $json['content']['named_imgs']['cover']['filename'];
```

### 2. riin-summaly (fruitriin/riin-summaly)

**仓库**: https://github.com/fruitriin/riin-summaly.git
**文件**: `src/plugins/komiflo.ts`

使用 `346_mobile` 作为默认尺寸:

```typescript
const PREFERRED_VARIANT = '346_mobile';
summary.thumbnail = `https://t.komiflo.com/${PREFERRED_VARIANT}/${filename}`;
```

---

## 附录: 完整变体列表

### 所有发现的变体

| 变体 | 数组 | CDN | 无认证 | 有认证 | 说明 |
|-----|-----|-----|--------|--------|------|
| `2500_desktop_large_2x` | r | cdn_public | - | ✗ Not Found | 最大主变体 |
| `2000_desktop_medium_2x` | r | cdn_public | - | ✗ Not Found | |
| `1500_desktop_small_2x` | r | cdn_public | - | ✗ Not Found | |
| `1250_desktop_large` | r | cdn_public | - | ✗ Not Found | |
| `1242_mobile_large_3x` | r | cdn_public | - | ✗ Not Found | |
| `1000_desktop_medium` | r | cdn_public | - | ✗ Not Found | |
| `828_mobile_large_2x` | r | cdn_public | - | ✗ Not Found | |
| `640_mobile_small_2x` | r | cdn_public | - | ✗ Not Found | |
| `625_desktop_large_half` | r | cdn_public | - | ✗ Not Found | |
| `500_desktop_medium_half` | r | cdn_public | - | ✗ Not Found | |
| `494_desktop_large_2x` | i | cdn_thumbs | ✓ 200KB | ✓ 200 | |
| `414_mobile_large` | r | cdn_public | - | ✗ Not Found | |
| `414_mobile_medium_2x` | i | cdn_thumbs | ✓ 142KB | ✓ 200 | |
| `396_desktop_medium_2x` | i | cdn_thumbs | ✓ 131KB | ✓ 200 | |
| `376_mobile_large_2x` | i | cdn_thumbs | ✓ 119KB | ✓ 200 | |
| `375_mobile_medium` | r | cdn_public | - | ✗ Not Found | |
| `346_mobile` | i | cdn_thumbs | ✓ 101KB | ✓ 200 | |
| `320_mobile_small` | r | cdn_public | - | ✗ Not Found | |
| `320_mobile_narrow_2x` | i | cdn_thumbs | ✓ 88KB | ✓ 200 | |
| `296_desktop_small_2x` | i | cdn_thumbs | ✓ 76KB | ✓ 200 | |
| `247_desktop_large` | i | cdn_thumbs | ✓ 54KB | ✓ 200 | |
| `207_mobile_medium` | i | cdn_thumbs | ✓ 39KB | ✓ 200 | |
| `198_desktop_medium` | i | cdn_thumbs | ✓ 36KB | ✓ 200 | |
| `188_mobile_large` | i | cdn_thumbs | ✓ 33KB | ✓ 200 | |
| `160_mobile_narrow` | i | cdn_thumbs | ✓ 24KB | ✓ 200 | |
| `148_desktop_small` | i | cdn_thumbs | ✓ 21KB | ✓ 200 | |
| **`564_mobile_large_3x`** | **i** | **cdn_thumbs** | **✓ 264KB** | **✓ 200** | **最大可用** |

---

## 测试日期

2026-06-04
