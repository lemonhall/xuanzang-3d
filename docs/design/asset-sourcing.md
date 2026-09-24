# 造像白膜从哪来：一次素材采购的完整记录

写这份文档的原因很直接：**下一次还要找这类素材**。

2026-09-24 那天要把幻景里的弥勒从汗地大肚弥勒换成犍陀罗风格，
「网上有没有免费白膜」这个问题花掉的工夫，比后面改代码多得多。
所以把**管线、坑、和判断依据**全部记下来，别只记结论。

---

## 0. 一页结论

| 项 | 值 |
|---|---|
| 选用 | **Mia 2001.153 Standing Buddha（犍陀罗，3 世纪）** |
| 来源 | 明尼阿波利斯美术馆，经 Objaverse 1.0 镜像到 Zenodo |
| 授权 | **CC0**（公共领域，零限制） |
| Zenodo record | <https://zenodo.org/records/10314513> |
| GLB | `1cd1470645334a76ae23b755b53fb736.glb`，5 361 468 字节 |
| SHA-256 | `b6d2cc719c2e91c0fb316619731680d2cd0160d707ea8045c9d545b3edb7c95c` |
| 网格 | 72 064 三角面、42 547 顶点、1 个材质槽 |
| 朝向 | **Z 轴向上**，**面朝 -Y**（转 -X 只需绕 Z 转 -90°） |

三条可以反复用的取数通道，按好用程度排：

1. **Objaverse 1.0 的 Zenodo 镜像** —— Sketchfab 上 CC 授权模型的免鉴权直下渠道（见 §1）。
2. **archive.org 的 thingiverse 镜像** —— 可全文检索，能按 `creator` 反查博物馆整批上传（见 §2）。
3. **美术馆自己的开放 API** —— 干净但覆盖窄，适合交叉验证馆藏号（见 §3）。

---

## 1. 意外收获一：Sketchfab 下不动，但它的模型躺在 Zenodo 上

### 表面现象

Sketchfab 的**搜索** API 是免鉴权的，能直接拿到 `uid` / 面数 / 授权：

```powershell
$env:HTTPS_PROXY='http://127.0.0.1:7897'
curl.exe -s "https://api.sketchfab.com/v3/search?type=models&q=gandhara%20buddha&downloadable=true&count=24"
```

返回里 `license.label` 会直接写 `CC0 Public Domain` / `CC Attribution` /
`CC Attribution-NonCommercial-ShareAlike`，`isDownloadable` 也标好了。

但**下载**是另一回事。实测：

```
GET https://api.sketchfab.com/v3/models/358a23bbb6634fd5986a335b6bff275d/download
HTTP 401
{"detail":"Authentication credentials were not provided."}
```

`/v3/models/{uid}/download` 要一个带 `download` scope 的 OAuth token。
没有 token，一条也下不动——**能看见不等于能拿到**。

### 绕法

**Objaverse 1.0**（Allen AI）当初批量抓取 Sketchfab 上 CC 授权的模型，
每个模型作为一条 **Zenodo record** 发布。Zenodo 的文件端点是免鉴权的：

```powershell
# 列表
curl.exe -s "https://zenodo.org/api/records?q=gandhara&size=25&page=1"

# 取模型（和取缩略图同一个前缀，只换文件名）
curl.exe -s -o model.glb `
  "https://zenodo.org/api/records/10314513/files/1cd1470645334a76ae23b755b53fb736.glb/content"
```

### 从 record 里读出什么

| JSON 字段 | 含义 | 怎么用 |
|---|---|---|
| `metadata.license.id` | **原始授权**（不是 Objaverse 的） | 决定能不能商用 |
| `metadata.creators[].name` | 原 Sketchfab 作者名 | 署名用 |
| `metadata.description` | 常写着 `Source: Objaverse 1.0 / Sketchfab` | 溯源 |
| `files[].key` 以 `.glb` 结尾 | 模型本体 | 下载目标 |
| `files[]` 里的 `thumb0..N.jpeg` | 多角度预览 | **先看图再下载**，省流量 |
| `doi` | `10.5281/zenodo.<id>` | 可引用的稳定标识 |

### 两个必须记住的细节

1. **匿名请求 `size` 上限是 25。** 写 `size=100` 不是被忽略，是直接
   `400 {"field": "size", "messages": ["Page size cannot be greater than 25..."]}`。
   要更多就翻页，或者走鉴权。
2. **缩略图和 GLB 同源同前缀**，只差文件名。所以「先抓 thumb、肉眼看、
   再决定下不下 30 MB 的 GLB」是完全可行的流程。这条在这次选型里省了
   大量下载时间——最后选的 01 是 5 MB，被否掉的最大一个有 108 MB。

---

## 2. 意外收获二：archive.org 的 thingiverse 镜像是个可检索的博物馆仓库

`collection:thingiverse` 是 Thingiverse 的完整镜像，`advancedsearch.php`
支持**全文**检索（标题 + 描述），而描述里往往带着**完整的博物馆著录**：

```
Seated Buddha
Culture: Northern Pakistan; perhaps Jamalgarhi; Peshawar valley; former kingdom of Gandhara
Medium: Schist
Accession Number: B60S393
```

看到这个就知道：**这是真品扫描，不是网友捏的**。而且 `Accession Number`
可以直接去博物馆官网核对。

### 按 creator 反查整批上传

这是最有用的一招——博物馆是以**账号**为单位批量上传的，找到账号就找到整批：

```powershell
# 大都会博物馆 2012 年 Met MakerBot Hackathon 那批：75 件
curl.exe -s "https://archive.org/advancedsearch.php?q=creator%3A%22The+Metropolitan+Museum+of+Art%22+AND+collection%3Athingiverse&fl%5B%5D=identifier&fl%5B%5D=title&rows=400&output=json"

# 亚洲艺术博物馆：10 件
curl.exe -s "https://archive.org/advancedsearch.php?q=creator%3A%22Asian+Art+Museum%22+AND+collection%3Athingiverse&fl%5B%5D=identifier&fl%5B%5D=title&rows=400&output=json"
```

单件元数据（含描述与文件清单）：

```powershell
curl.exe -s "https://archive.org/metadata/thingiverse-24124"
```

### 关键词命中表（本项目的实测结果）

| 关键词 | 命中 | 说明 |
|---|---|---|
| `gandhara` | 2 | 只有亚洲艺术博物馆的 Seated Buddha 是真的 |
| `gandharan` | 3 | 都是**浮雕**（大都会那批 schist 板），没有立体造像 |
| `hadda` | 2 | 一个佛头（大都会 1986.2，粘土） |
| `peshawar` / `taxila` / `maitreya` | 2 / 1 / 10 | 基本被无关条目稀释 |
| `schist` | 16 | 石材词能捞到犍陀罗，但混进一堆埃及和印度件 |

**结论：Thingiverse 上没有犍陀罗立体造像，只有浮雕。** 这条结论本身就是收获，
省得下次再翻一遍。

速度坑沿用 `assets/statue/CREDITS.md` 里那条：同一条直链，
`/download/` 走代理只有 5 KB/s，换成 `/serve/` 实测 9.5 MB/s，差 1800 倍。

---

## 3. 意外收获三：美术馆自己的开放 API 适合做交叉验证

### 克利夫兰美术馆（CMA）

`openaccess-api.clevelandart.org` 免鉴权，而且**记录里直接有 `sketchfab_id`**，
等于把「馆藏号」和「Sketchfab uid」焊在了一起：

```powershell
curl.exe -s "https://openaccess-api.clevelandart.org/api/artworks/147010"
```

对 `?q=buddha&limit=100` 的结果过滤 `sketchfab_id` 非空，在 274 条里挑出 23 件有 3D 的，
其中 `1967.39 Seated Buddha`（阿富汗 Hadda，很可能 Tape Shotor）是犍陀罗圈的。

注意：**CMA 有 `sketchfab_id` ≠ 你能下载**。它只是替你省掉了「这件有没有 3D」的猜测，
真要拿文件还是得回到 §1 的 Zenodo 通道去找同一个 uid。

### 维基共享（Wikimedia Commons）

检索语法只有 `filetype:3d` 是有效的：

| 查询 | 命中 |
|---|---|
| `filetype:3d buddha` | 6（含史密森尼上传的 Cosmic Buddha STL） |
| `filetype:3d Smithsonian` | 384 |
| `filetype:stl Smithsonian` | **0** |
| `filetype:3d gandhara` | **0** |

所以 Commons 上**没有**犍陀罗 3D。但它是一份好的「博物馆把 STL 直接放进 Commons」
的样板（`Category:CC-Zero`），值得记住这个模式。

---

## 4. 死路清单（别再试了）

| 试过的 | 结果 |
|---|---|
| `api.sketchfab.com/v3/models/{uid}/download` | `401 Authentication credentials were not provided` |
| `html.duckduckgo.com/html/?q=` | `202`，返回 14 KB 挑战页，无结果 |
| `lite.duckduckgo.com/lite/?q=` | 同上，`202` |
| `www.bing.com/search?q=` | `200` 但正文是 JS 壳，正则取不出结果 |
| `www.references3d.com/fichier/buddha-debout/` | `404`（站点已改版或下线） |
| `3d-api.si.edu/search?q=` | `404` |
| `3d-api.si.edu/content/search?q=` | `404` |
| `3d.si.edu/api/search?q=` | `403` |
| `commons.wikimedia.org/...srsearch=filetype:stl` | `0` 命中（语法不存在） |
| `zenodo.org/api/records?...&size=100` | `400`，匿名上限 25 |
| `api.printables.com/graphql`（自拟 `searchModels2`） | `400 Cannot query field`（query 名不对，未继续深挖） |

---

## 5. 候选清单（当时的完整横向对比）

授权列是**最终裁决依据**。CC0 > CC BY > CC BY-NC-SA，越往右枷锁越紧。

| # | 造像 | 出处 / 年代 | 授权 | GLB | 形态 | 结论 |
|---|---|---|---|---|---|---|
| **01** | **Standing Buddha** | **Mia 2001.153，犍陀罗，3 世纪** | **CC0** | 5.4 MB | **完整独立立像** | **✅ 选用** |
| 02 | Seated Buddha（带背光） | 以色列博物馆，犍陀罗，3–4 世纪 | CC BY 4.0 | 31.8 MB | 残缺浮雕构件 | 辨识度最高，但侧背是断口 |
| 03 | Buddha Standing | Geoffrey Marchal | CC BY-NC 1.0 | 18.1 MB | **头缺失** | ✗ 没有头 |
| 04 | Bodhisattva（头后有圆光） | Geoffrey Marchal | CC BY-NC 1.0 | 17.1 MB | 立像上半身 | ✗ NC 授权 |
| 05 | Head of the Buddha | Rijksmuseum | CC BY 4.0 | 5.1 MB | 仅头像 | 只适合「沙里露一颗头」 |
| 06 | Head of Buddha | 芝加哥艺术博物馆 | CC BY 4.0 | 108.1 MB | 仅头像 | 同上，且体积过大 |
| 07 | Gandharan Buddha Pediment Fragment | frankmcmains | CC BY 4.0 | 8.0 MB | 建筑构件 | 像文物，不像巨像 |
| 08 | Bodhisattva Maitreya Head | 3DSCANFR | CC BY 4.0 | 2.1 MB | 仅头（戴宝冠） | 仅头像 |
| 09 | Ghandhara Buddha | Scan-the-World | CC BY-NC-SA 4.0 | 3.1 MB | — | ✗ NC + SA |
| 10 | Bodhisattva Maitreya | Guimet 美术馆 | CC BY-NC-SA 4.0 | 7.2 MB | 立像 | ✗ NC + SA |
| 11 | Bodhisattva Maitreya | 冬宫博物馆 | CC BY-NC-SA 4.0 | 0.4 MB | — | ✗ NC + SA，且过小 |
| 12 | Seated Buddha | 亚洲艺术博物馆 B60S393（Jamalgarhi） | CC BY-SA 3.0 | — | 坐像 | ✗ SA |
| 13 | Seated Bodhisattva Maitreya | 大都会 20.58.15（喀布尔附近，片岩） | CC BY-SA 3.0 | — | 坐像 | ✗ SA，且 2012 年 123D Catch 扫描粗糙 |
| 14 | 汗地大肚弥勒（ruyimile.stl） | Thingiverse 2431705 / stronghero | CC BY 3.0 | 175 MB | 立像 | ✗ 风格不符，已弃用 |

**许可上的分水岭**：`-NC` 禁止商用，`-SA` 要求衍生作品采用同样许可。
后者的实际后果是——一旦把这个 GLB 放进仓库并分发，**那份 GLB 必须继续以
BY-SA 分发**。对一个可能被商用、或以其他许可开源的作品，这是个真约束。
CC0 没有任何这类问题，这也是 01 胜出的**决定性理由**，不是附带好处。

---

## 6. 为什么最终是 01

三条硬指标，01 是唯一同时满足的：

1. **完整**。是一尊可以 360° 看的独立立像，不是浮雕残件、不是只有头。
   幻景里它要被绕着看、被逆光照，残件在转角度时会露馅。
2. **CC0**。见 §5 末尾那条分水岭。
3. **立姿**。玄奘是**走向**它的，立像让「走过去」这个动作成立；
   坐像会把构图变成「走到跟前坐下」。

视觉上它同时也是最犍陀罗的一尊：希腊化的面容、波浪形发髻加肉髻、
通肩袈裟的厚重垂褶、赤足站在刻了人物的台座上。**它的弱点是立佛的剪影
本来就接近「穿长袍的希腊哲人」**——所以「这是佛」这件事不能只靠像身，
要靠场景里那圈举身光和逆光来点明。这条结论直接影响构图，写在这里备查。

关于命名的一点诚实说明：Mia 给这件作品的定名是 **Buddha**（释迦牟尼），
不是 Maitreya。犍陀罗艺术里两者靠**装饰**区分——弥勒菩萨戴璎珞、臂钏、
发髻束冠、手持净瓶，而佛陀是素面僧衣。场景叙事里它承担的是玄奘的
**弥勒信仰**（他一生念弥勒、求生兜率天），而弥勒作为**未来佛**本就有
佛形的一相。是否在游戏文案里改称呼，由柠檬叔定。

---

## 7. 复现命令

```powershell
$env:HTTP_PROXY='http://127.0.0.1:7897'; $env:HTTPS_PROXY='http://127.0.0.1:7897'

# 1. 看 record 元数据（授权 / 文件 / 缩略图清单）
curl.exe -s "https://zenodo.org/api/records/10314513"

# 2. 先抓缩略图目视挑选（每张几 KB，比下 GLB 便宜得多）
foreach ($i in 0..4) {
  curl.exe -s -o "thumb$i.jpg" `
    "https://zenodo.org/api/records/10314513/files/thumb$i.jpeg/content"
}

# 3. 再下模型
curl.exe -s -o artsmia-gandhara.glb `
  "https://zenodo.org/api/records/10314513/files/1cd1470645334a76ae23b755b53fb736.glb/content"

# 4. 核验
(Get-Item artsmia-gandhara.glb).Length          # 应为 5361468
(Get-FileHash artsmia-gandhara.glb -Algorithm SHA256).Hash
```

期望哈希：`b6d2cc719c2e91c0fb316619731680d2cd0160d707ea8045c9d545b3edb7c95c`

---

## 8. 一句话对照：CC 授权怎么挑

| 授权 | 商用 | 改作 | 必须署名 | 衍生作品必须同授权 | 本项目 |
|---|---|---|---|---|---|
| CC0 / 公共领域 | ✅ | ✅ | ❌ | ❌ | **首选** |
| CC BY | ✅ | ✅ | ✅ | ❌ | 可用 |
| CC BY-SA | ✅ | ✅ | ✅ | **✅** | 会把 SA 传染给 GLB |
| CC BY-NC / -NC-SA | **❌** | ✅ | ✅ | 视后缀 | 个人项目勉强，正式发布不行 |

**采购顺序：先按授权筛，再按造型挑。** 反过来的话，会在看中一尊之后
才发现它不能商用。
