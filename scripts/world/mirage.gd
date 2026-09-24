class_name Mirage
extends Node3D

## 楼兰幻影：沙尘里升起的一座巨城，宽 4.4 km、主塔 1500 m。
##
## 尺寸是真实佛塔的四十倍。既然放大了，**细节也必须配得上这个尺度**：
## 一百多个部件堆出来的轮廓只有六七个转折，一看就是"几个圆柱摞起来"；
## 真实建筑在远处显得复杂，是因为它有几百个转折。所以这里的目标是
## 三千多个部件，全部合成单个 mesh。
##
## 细节都花在**剪影**上，因为两千五百米外真正能被看见的只有轮廓：
##   方台五层递收 + 上下线脚 + 每边三十六个壁龛 + 四角角柱
##   台顶一圈栏杆望柱
##   塔身七十二道竖壁柱 + 十二道腰线（每道五十六个凸块）+ 三圈佛龛带
##   覆钵圆顶 + 一圈莲瓣
##   十三层相轮，每层边缘三十二颗珠串 + 华盖
##   四角各一座小窣堵坡
##
## 巨物恐怖不靠"占满画面"。这一版把上一版的教训写在这儿，别改回去：
##
##   **把东西塞满屏幕，得到的是天花板，不是巨物。**
##
## 上一版把幻影放到玩家前方 250 m、整体 0.55 倍，城郭横着切出画外、
## 城门楼顶到 63°。角度上它已经"装不下"了，但玩家抬头一看是**穹顶**：
## 城墙像一圈护墙板、角楼的攒尖顶像天花板的梁、天光从地平线（也就是
## 房间地面的灯槽）打上来。因为"围着人"和"压着人"在视觉上是同一件事，
## 而"围"就等于"室内"。
##
## 巨物恐怖真正的来源是**量不出来**，而量不出来有三条路，和"占满画面"无关：
##   1. **横向量不出来**：墙的左右两端都在画面之外（±57°，半视角只有 48°）；
##   2. **纵深量不出来**：近墙 1.4 km、远墙 5.8 km，后半座城化在沙尘里；
##   3. **顶量不出来**：主塔 1500 m、顶端 32° 还在画面内，但上半截**溶进天空**。
## 三条都成立时，玩家知道它很大，却找不到任何一条可以量的边——而头顶
## 30° 以上全是干净的天。这才是"巨物"，不是"屋顶"。
##
## 距离与高度的配比（本版的核心数字，改任何一个都要重新验算）：
##   正面城墙 1770 m 外、400 m 高 → 12.5°（贴着地平线站起来的一条横带）
##   城门楼   1770 m 外、620 m 高 → 19°（画面正中的第二个高点）
##   主塔     2900 m 外、1500 m 高 → 27.5°（城郭的最高点）
##   角楼     3140 m 外、520 m 高  → 9.4°、方位 ±52.8°（转头的瞬间才进场）
## 换句话说：**真身比上一版大 2~3.5 倍，看出去的角度反而小了**——
## 挪远不是缩小，是把"贴脸"换成"远到量不出来"。
##
## 上面的四个数字是**城郭**的。这一版真正的最高点是弥勒像：
## 像头 66.7°、举身光尖 70.5°——它们**故意**在画面之上（见下面"尺度"那段）。

## 主塔整体放大倍率（塔的造型代码按 820 m 写，乘完是 1500 m）。
const TOWER_SCALE := 1.83
## 主塔中心离**正面城墙**的距离（米）。塔必须在城的前半部：
## 城正中心离玩家 4400 m，同样 1500 m 只能顶到 19°，会被 620 m 的城门楼压住；
## 放在城墙后 1000 m 处（离玩家 2900 m）才够 27.5°，而且是**城郭里**唯一的
## 最高点（全场最高点从这一版起归弥勒像，见下面"尺度"那段）。
const TOWER_BEHIND_WALL := 1000.0

## --- 弥勒大像 ---
##
## 幻景里唯一的人形。塔再高也只是"一根柱子"，人形一立起来，玩家会本能地
## 拿自己去比——这是整套尺度感里最便宜也最狠的一招。
##
## 为什么是弥勒：玄奘一生念弥勒、求生兜率天，《大唐西域记》里他亲笔记下
## 梵衍那国（巴米扬）"高百四五十尺"的立佛石像。他是在沙漠里抬头看过巨像、
## 并且把它写进书里的人。所以这尊像不是装饰，是**他自己的执念**——
## 幻景本来就由"渴"和"沙暴"驱动，他渴到极点时看见的，当然是他念了一辈子的那位。
##
## 一句要诚实的话：犍陀罗艺术里，弥勒菩萨（戴璎珞、束发、持净瓶）和释迦佛
## （素面僧衣）是**靠装饰区分**的，而选中的白膜是素面僧衣的佛形。这不矛盾——
## 弥勒作为**未来佛**本来就有佛形的一相；而且场景要的是"一尊认得出的犍陀罗
## 造像"，不是一件拿去做图像学考据的标本。
##
## 人形高度就是它自己的尺度参照，所以它必须是全场的顶点。
##
## 它**站在城墙前面**，不是在城里：背后有城郭做底、脚下有沙脊切边，
## 剪影才立得住。埋在城里的像只会和城墙糊成一团——第一版就是这么糊的。
##
## 高度是**巴米扬大佛的近二十倍**（那尊"高百四五十尺"的立佛，玄奘亲笔记过），
## 也就是 1080 m。这个数字不是随便定的：玩家对"像"的尺度判断全靠人形比例，
## 而"二十倍"正好是原案里楼兰建筑的量级。
##
## ### 像身是一份**外部白膜**，不是程序化堆的方块
##
## 曾经这里用 BoxMesh / CylinderMesh / SphereMesh 堆了一尊像，结果是一根
## 桶形身子顶着一颗说不出形状的头、脖子上串一圈珠子。**"看不出是什么"
## 不是意外，是必然**：程序化基本体表达不了面部、体态和衣纹，而这三样
## 恰好是"这是一尊造像"的全部内容。
##
## 现在是一份外部白膜，而且**必须是犍陀罗的**。为什么：
##
## 玄奘走的这条路，起点就是犍陀罗（今白沙瓦一带）。犍陀罗造像正是
## 希腊化面孔 + 通肩袈裟 + 波浪发髻＋肉髻那一套——它本来就是"希腊人
## 给佛画的像"，是**玄奘亲眼见过的那个佛的样子**。汗地那种大肚笑弥勒
## 是几百年后、几千里外的另一条支线，放进塔克拉玛干是年代和地理双错。
##
## 选型过程、候选对比、授权分水岭见 `docs/design/asset-sourcing.md`。
## 当前这份是明尼阿波利斯美术馆 Mia 2001.153 犍陀罗立佛（3 世纪），
## **CC0**（无署名义务，我们照署），见 `assets/statue/CREDITS.md`。
## 由 `blender/build_gandhara_buddha.py` 归一化：
## 脚底 y=0、轴心在正下方、总高 STATUE_HEIGHT、面朝 -X。
##
## ### 尺度：**4 倍**，而且**故意装不进画面**
##
## 前两版按"整尊必须装得进水平前视"解构图（像头 30.3°、画面上沿 34°），
## 读出来是"看得见，但它只是远处的一尊像"。需求方的判断是
## 「佛还是不够巨物感……你先放大个 4 倍看看」，随后定为
## 「上放大 4 倍的那个」。**所以设计态就是 4 倍**：
##
##   像高 4320 m、埋掉的台座 691 m、沙面之上的像头 3629 m、光尖 4428 m。
##
## 空间尺度（实测，改常数必须重测）：
##
##   水平前视：画面上沿 34° 只切到像的**膝下**那一段——一堵从沙脊线上
##   立起来的僧袍的墙，左边切出画外，宽窄量不出来。像头 66.7°、
##   举身光尖 70.5°，都在画面之上：**装不下，才是巨物**。
##
##   抬头：俯仰上限 77.3°，像头 66.7°。抬头 33° 起就能看见佛头，
##   抬头 40° 时整尊像连光背一起进画面。**脸没有丢，只是要仰头看。**
##
##   这跟上一版被骂过的"没有头"是两件事，别混：那次是像顶 37.6° 而画面上沿
##   只有 34°，**抬头也追不上**——够不着。这一版是够得着，只是不给你白看。
##
##   主塔 27.5°：同一个幻影里，1500 m 的塔在这尊像面前是个小件。
##   巨物要有唯一的顶点，但**顶点不必装进画框**。
##
## 4 倍顺带把"虚幻"放大了，这也是需求方自己点出来的
## （"佛像变得很虚幻的一版，我其实很喜欢"）。原因在着色器里：空间溶解
## 噪声的域尺度是 0.0025（≈400 m 一个瓣），1 倍时整尊像只横跨两三个瓣、
## 轮廓是硬的；4 倍横跨十几个瓣，边被啃成大片柔软的涡，像退回到沙尘里。
## **这是加分项，别再当成瑕疵"修"掉。**
##
## 观距**不跟着倍率走**：放大不改观距。像的轴线在正前方 1420 m、横向偏
## 700 m（斜距 1570 m），这个位置由 main.MIRAGE_FRONT_WALL 钉死，
## 玩家走多近它都退多远。
##
## **三份材质**（这一版的关键结构，别再合并回去）：
##
## 城郭和像身共用 `mirage.gdshader` 但各拿一份材质参数，因为两者对
## "折射 / 溶解 / 亮度"的要求正好相反；举身光是第三份，走另一支着色器：
##
##   城郭   折射 96 m —— 它本来就是"一片建筑"，切成几十段照样读得出是城；
##   像身   折射 10 m —— 人形是全场景唯一的"人"，切一刀就从一个人变成
##                        一摞盘子。上一版就是把它和城郭一起扭，扭没了。
##   举身光 **另一支**着色器 —— 它必须是**加色**（blend_add）而不是混色：
##                        混色的话它和像身同为"白色半透明"，两层白一叠，
##                        像就融进自己的光里了。形状也不一样：城郭和像身
##                        是"几何用什么就是什么"，举身光是一枚平的圆环面，
##                        粗细、光焰、软边全在 fragment 里画。
const STATUE_HEIGHT := 1080.0
## 像身倍率。**4.0 就是设计态**（需求方 2026-09-24 指定"上放大 4 倍的那个"），
## 不是调试旋钮：1.0 = 白膜原尺寸（STATUE_HEIGHT）。
##
## 它只放大像身和举身光，城郭一动不动——城是"回不去的地方"，尺度是它的设定；
## 像才是这一关要"压住画面"的那一件。
##
## 两件必须一起记住的事：
##
##   1. **放大不改观距**。幻影离玩家多远由 main.MIRAGE_FRONT_WALL 决定，
##      跟这里无关。所以像头仰角随倍率线性上涨（1 倍 30.3° → 4 倍 66.7°），
##      而"整尊装进画面"这条旧约束在 4 倍下**自动失效**——现在的契约是
##      "装不下、但抬头够得着"（见文件头"尺度"那段）。
##
##   2. **举身光的形状跟着一起走**。环的半径、亮带的粗细 σ 都是按当前像高
##      算出来的（`halo_ring_core()` / HALO_BAND_SIGMA_RATIO），材质那五个
##      `ring_*` uniform 也在 _make_halo_material() 里现算。
##      漏掉哪一处，光环都会缩在脚脖子上或者涨成一根铁丝。
##
## 为什么是 static：值必须在 Mirage._ready() 拼几何**之前**写进去，而
## 场景里的 Mirage 是 main._ready() 建的。测试会钉住这个默认值，
## 不让它被某个调试开关悄悄改掉。
static var statue_scale := 4.0
## 台座在白膜里占的高度比例（占像高）。**量出来的，不是拍的**。
##
## 这份扫描件在脚踝以下还带着博物馆的展台：一块方墩子，有线脚、
## 角上有立柱。它是整份白膜最"出戏"的地方——摆在 1.8 km 外，它会从
## 沙脊线上沿探出来，读起来不是"一尊从沙里站起来的像"，而是"一个摆在
## 台子上的模型"。台座一露，比例尺就露了：观众能一眼看出底下是个方墩子，
## 于是一尊 1080 m 的像立刻降级成一件摆在展台上的石雕。
##
## 量法（两个口径对上才算数）：
##   * `blender/build_gandhara_buddha.py` 的高度剖面：0~15% 那一层的前后跨度
##     是 111→140 m 的缓坡（方墩子的收分），16% 起才变成脚和衣裾；
##   * `_agent_tmp/new-statue-views/posY.png` 正交侧视图：像身占 y 45~940 px，
##     方墩子占 y 800~940 px —— **(940-800)/895 = 15.6%**。
## 两边一致，取 16%。**埋掉它同时是"巨物感"的一部分**：像从一个看不见的
## 底座里长出来，底下还有多少截、脚下踩着什么，全都量不出来。
##
## 写成比例而不是米数：台座是白膜的属性，`statue_scale` 一变（见上）
## 它必须跟着变，否则放大到 2 倍时台座又会露出来。
const STATUE_PEDESTAL_RATIO := 0.16
## 像身白膜的路径。`.glb` 由 `blender/build_gandhara_buddha.py` 生成，
## 已经归一化过：脚底 y=0、轴心在正下方、总高 STATUE_HEIGHT、面朝 -X。
## 所以这里**不需要再缩放也不需要再旋转**——加它的时候用单位变换就行。
## 再缩放一次就等于把这个契约复制了一份，两边一改就对不上了。
const STATUE_MESH_PATH := "res://assets/statue/gandhara-buddha.glb"
## 头顶在像高里的位置。白膜上量出来的：**1.000h**。
##
## 上一版（大肚弥勒）是 0.888h，因为那尊把如意举过了头顶，像顶是如意不是头。
## 这尊立佛没有举起来的东西——量过最顶的那颗顶点，落在中轴附近（横向 1 m），
## 就是肉髻尖，**头顶就是像顶**。所以这里写 1.0，而不是照抄上一版的 0.888。
##
## 这个数字决定"水平前视能不能看见佛头"，也就是"这尊像有没有头"。
## 抄错一位，画面上就是一尊没有头的巨像（上一版真踩过，见文件头）。
const STATUE_HEAD_RATIO := 1.000
## 举身光顶点 / 全场天际线：着色器的冷暖渐变按它归一化。
## --- 举身光（那圈光）---
## 环心高度：0.745h，落在肩后、胸口之上。再高就成了顶帽子，再低成了个项圈。
const HALO_CENTER_RATIO := 0.745
## 环的外半径 / 内半径（像高比例）。
##
## 上一版 0.196h/0.260h 的环**太小了**：那尊白膜腰身最宽处 0.284h（307 m），
## 比内径 212 m 还宽——环的下半圈整个埋在肚子和袖子里，露出来的那几段
## 看起来像套在身上的呼啦圈，不像从背后透出来的光。
##
## 举身光要读成"围在像身外的一圈"，**内径必须大于像身最宽处**。
## 换成犍陀罗立佛之后这两个数都变了（立像比坐像/大肚像窄得多）：
##
##   像身最宽半宽 0.177h = 191 m（在 0.64h，僧袍下摆那一层）
##   环的内半径   0.310h = 335 m
##
## 余量从 1.09 倍放宽到 1.75 倍。**这个余量是有意义的，不要为了"贴紧"
## 把它收掉**：环的外径 0.380h 意味着整圈光背比像身还矮（0.820h < 1.0h），
## 于是头顶从环的上弧之上顶出来、腿从下弧之下露出来，中间那截被光围着——
## 这正是"背光"的读法。收窄内径会让环重新落回身体轮廓里，回到呼啦圈。
const HALO_OUTER_RATIO := 0.380
const HALO_INNER_RATIO := 0.310
## 光焰（环外缘之外那圈短刺）的半长。光焰的**内端**接在环外缘上，
## 尖端到 `外径 + 两个半长`。
##
## 这一版它**不再是一根根几何**了：上一版是 28 根等长等宽的方条，
## 4 倍之后变成一圈整齐的齿（需求方："那个光环有点不自然"）。现在光焰是
## 着色器里的角度噪声，这个数退化成"光焰最多能伸多远"的标尺。
const HALO_RAY_HALF_RATIO := 0.030
## 光的尽头（像高比例）：环的外径 + 一整个光焰。几何的圆环面就画到这儿，
## 外侧的亮度由着色器的光雾尾巴收到 0——**外缘不能有边**。
const HALO_TIP_RATIO := HALO_OUTER_RATIO + HALO_RAY_HALF_RATIO * 2.0
## 主亮带的粗细 σ（像高比例）。**这是屏幕上那圈光有多厚**，和几何无关：
## 环面是一枚平的圆环，厚度全在这一个数里（见 shaders/mirage_halo.gdshader）。
##
## 0.013h 在 1 倍时是 14 m、4 倍时是 56 m → 半高全宽 2.36σ ≈ 3.4°，
## 默认机位上是一条 40 px 的光带。上一版那根管子是 0.07h，4 倍之后 302 m 粗、
## 屏幕上 110 px 宽的一条亮带——那就是"塑料管"的来历。改这个数等于改环的粗细。
const HALO_BAND_SIGMA_RATIO := 0.013
## 环面的分段数与径向层数。192 段 = 每段 1.9°，4 倍时外缘的弦长约 62 m，
## 默认机位约 3 px——再少就能看出多边形的折角。
const HALO_SEGMENTS := 192
const HALO_RADIAL_RINGS := 6
## 举身光的**真实**顶点（米）。测试和截图诊断都读它：上一版代码画到 1.02h，
## 诊断却按 1.22h 量，"举身光顶 45.7°"那个数字一直是编出来的。
const HALO_TOP := STATUE_HEIGHT * (HALO_CENTER_RATIO + HALO_TIP_RATIO)


## 像身**当前**的高度（米）。设计值是 STATUE_HEIGHT；调试倍率非 1 时
## 像身、举身光、以及所有"像高比例"都跟着乘同一个数——三样必须一起走，
## 否则光环会留在脚脖子上。诊断和测试读这个，不要各自乘一遍。
static func statue_height() -> float:
	return STATUE_HEIGHT * statue_scale


## 台座要埋掉多少米。白膜的原点在台座**底面**，往下降这么多之后，
## 展台正好落到沙面以下——`statue_offset()` 的 y 就是它。
static func statue_sink() -> float:
	return statue_height() * STATUE_PEDESTAL_RATIO


## 像头（= 像顶）离幻影节点原点的**高度**（米）。已经扣掉下沉量。
##
## 测试和截图诊断都必须读这个，不要再各自写 `STATUE_HEIGHT * HEAD_RATIO`：
## 那个数字是"白膜的顶"，不是"沙面之上还有多高"，差着一个台座。
static func statue_top_y() -> float:
	return statue_height() * STATUE_HEAD_RATIO - statue_sink()


## 举身光当前顶点高度（米）。同上，扣掉下沉量。
static func halo_top_y() -> float:
	return HALO_TOP * statue_scale - statue_sink()


## 主亮带的半径（米）：内径与外径的中间。屏幕上那圈最亮的光就画在这条线上。
##
## **几何和着色器读同一个出口**：几何的圆环面从 `内径` 铺到 `光焰尖`，
## 而亮带画在哪一条半径上由这里说了算。两处各写一遍的话，环会歪着——
## 亮带偏到洞里去，或者偏到光焰外面去，屏幕上都不像"出错"，只像"没调好"，
## 那是最难查的一类问题。
static func halo_ring_core() -> float:
	return statue_height() * (HALO_INNER_RATIO + HALO_OUTER_RATIO) * 0.5
## 着色器里冷暖渐变的**刻度上限**（归一化高度）。比实际最高点（主塔 1498 m）
## 还高，好让最高的那截继续往冷处走——它就是在溶进天空。
## 注意：这是标尺，不是"最高点"的备份。改它等于给全场重新配色。
const SKYLINE_HEIGHT := STATUE_HEIGHT * 1.22
## 像身站位：在正面城墙**之前** STATUE_FRONT_OF_WALL 米。
##
## 这一段改过两次，原因不同，别把后面那次当成前面那次的注脚：
##
##   1. 换白膜：大肚弥勒把如意举过头顶，像顶是如意、头顶只到 0.888h；
##      犍陀罗立佛**头顶就是像顶**（1.000h），"水平前视能看见佛头"
##      这条约束一下紧了 12.6%，于是往城里退了 100 m（300 → 200）。
##
##   2. 埋台座（**本版**）：白膜原点在台座底面，埋掉 16% 的展台之后，
##      沙面之上的像比白膜的顶点矮 173 m，像头仰角从 31.1° 掉到 26.7°——
##      而主塔顶是 27.5°。**主塔反超了**，测试当场喊"巨物要有唯一的顶点"。
##
##      修法两条：把塔压低，或者把像挪近。选了后者——台座是白膜自带的
##      麻烦，代价不该由塔来付；而且挪近正是"巨物感"要的方向。
##      观距 1827 → 1547 m（200 → 480），像头回到 30.4°：
##        * 像头 30.4° < 画面上沿 34°——余量 3.6°，比埋台座之前还宽；
##        * 像头 30.4° > 主塔顶 27.5°——唯一的顶点回来了；
##        * 举身光平面离城墙前表面还有 305 m（480 − 151 的环心偏移）。
const STATUE_FRONT_OF_WALL := 480.0
## 横向偏移（米，负 = 玩家左手边）。
## 两尊巨物不能压在同一根轴线上：叠在一起只剩一团分不清的轮廓。
## 错开 31°，才能一眼读出"一尊像"和"一座塔"是两个量级的东西。
const STATUE_SIDE := -700.0

## 城郭的折射强度（米）。1.4 km 外 96 m ≈ 4°，一转头就能看出"它在晃"。
const CITY_SHEAR := 96.0
## 像身的折射强度（米）。**刻意压到城郭的十分之一**：人形靠轮廓立命，
## 轮廓一断，"这是尊像"就没有了。它的"蜃"由举身光和逆光负责，不由剪切负责。
const STATUE_SHEAR := 10.0
## 肩半宽（像高比例）。白膜上量出来的：环心高度（0.745h）那一层，横向
## 半宽 0.152h（164 m），里面装着肩、垂手和僧袍的外沿。
## 环的内径（0.310h = 335 m）必须大于它——洞比肩宽，头肩才从环里透得出来。
##
## 这个常量现在**不再只是注释里的一个说法**：测试会拿它和实际 mesh 在
## 同一高度量出来的半宽对账（±15%）。白膜再换一次而这里忘了改，测试会喊。
const STATUE_SHOULDER_RATIO := 0.152
## 举身光的环心比像身轴线**靠后**多少（像高比例）：0.140h 在背光位，
## 正好落在肩后——光背要"从身后透出来"，不能糊在胸口上。
const HALO_BEHIND_RATIO := 0.140

const TIER_WIDTHS := [320.0, 292.0, 266.0, 242.0, 220.0]
const TIER_HEIGHTS := [34.0, 32.0, 30.0, 28.0, 26.0]
const TIER_BASES := [0.0, 34.0, 66.0, 96.0, 124.0]
const TERRACE_Y := 150.0
const TERRACE_HALF := 110.0

const NICHE_PER_SIDE := 36
const BALUSTRADE_POSTS := 44
const BODY_RIB_COUNT := 72
const BODY_BAND_COUNT := 12
const BODY_BAND_STUDS := 56
const SHRINE_BANDS := 3
const SHRINE_PER_BAND := 72
const FINIAL_COUNT := 13
const BEADS_PER_RING := 32

const CORNER_TOWER_OFFSET := 100.0
const BODY_BOTTOM_R := 100.0
const BODY_TOP_R := 76.0
const BODY_HEIGHT := 290.0
const DOME_R := 76.0
const DOME_H := 100.0
const TOTAL_HEIGHT := 820.0 * TOWER_SCALE

# --- 城郭 ---
# 只有一座塔是"一根柱子"，一座城才有"回不去的地方"的意思。
# 城墙把主塔围在中间，也让轮廓从"竖着的一根"变成"铺开的一片"。
## 城郭半宽。它决定"横向能不能切出画外"——只要城墙的左右两端还留在画面里，
## 大脑就会量出它的尺寸，那它就只是"一座大一点的城"。
##
## 2500 m 是被**观距**反推出来的，不是拍脑袋：城墙挪到 1900 m 之后，
## 2200 m 的半宽只剩 ±49.2°，而水平半视角是 50.2°——两端会露进画面。
## 2500 m 给出 ±52.8°，留 2.6° 余量。改城墙距离必须同时改这个数。
const CITY_HALF := 2500.0
const WALL_H := 400.0
const WALL_T := 260.0
const BATTLEMENTS := 96
const BASTION_TIERS := [560.0, 440.0]
const BASTION_H := 200.0
const GATE_HEIGHT := 620.0

## 部件按材质分桶。`_bucket` 是"现在往哪个桶里放"——造型代码完全不用
## 关心这件事，只由 _design() 换桶。合成 mesh 时一个桶一次绘制。
##
## 只有两个桶：城郭和举身光。**像身不在里面**——它是一份外部白膜，
## 整份就是一个 mesh，直接用，不需要（也不应该）和基本体合并。
enum { BUCKET_CITY, BUCKET_HALO }

var presence := 0.0

var _material: ShaderMaterial
var _statue_material: ShaderMaterial
var _halo_material: ShaderMaterial
var _parts: Array[Dictionary] = []
var _parts_halo: Array[Dictionary] = []
var _bucket := BUCKET_CITY
var _base_y := 0.0
## 当前正在拼装的部件用的整体缩放 / 平移。主塔用它放大并前移，
## 城郭保持 1:1（真实米）。
var _part_scale := 1.0
var _part_offset := Vector3.ZERO


func _ready() -> void:
	_material = _make_city_material()
	_statue_material = _make_statue_material()
	_halo_material = _make_halo_material()

	_design()

	# 一个桶一次绘制。分开挂两千个 MeshInstance3D 是两千次绘制调用，
	# 换一个两公里外、半透明、还看不清的东西——没有道理。
	_add_instance("Loulan", _parts, _material)
	# 像身是外部白膜：整份一个 mesh，第一次绘制而不是几千次。
	# 偏移必须显式传：像身走的是"读文件"这条路，不经过 _xform，
	# 不会自动带上 _part_offset。
	# 倍率同理：白膜是按 STATUE_HEIGHT 归一化的，这里乘 statue_scale 就等于
	# 把整尊像连同举身光一起放大——城郭一点不动。
	_add_mesh_instance(
		"Statue", _load_statue_mesh(), _statue_material, statue_offset(), statue_scale
	)
	_add_instance("Halo", _parts_halo, _halo_material)

	visible = false


## 三个 mesh 共用的那部分参数。放一个地方，免得三份材质各写一遍还写歪了。
func _base_material(shader_path: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load(shader_path)
	# 归一化高度取的是**冷暖刻度的上限**（SKYLINE_HEIGHT，2714 m），不是主塔。
	# 主塔 1500 m 于是落在 0.55 处、像头 0.85 处、环顶 0.43 处——
	# 冷暖渐变才有地方落。
	material.set_shader_parameter("y_range", Vector2(0.0, SKYLINE_HEIGHT))
	material.set_shader_parameter("strength", 0.0)
	# 下缘：幻影的底正好卡在前方沙丘脊线上，那里若是一条干净的硬边，
	# 看起来就像贴着地平线的贴纸。让它化进沙尘里，才像"从沙里凝出来的"。
	material.set_shader_parameter("low_fade", 0.045)
	# 1.3 km 处透射 0.75、5.8 km 处 0.28：近处的城郭站得住，
	# 后半个城先褪色再消失。
	#
	# 这个系数是**跟着观距走的**：城从 1.4 km 挪到 1.9 km 之后，原值会让
	# 近墙凭空淡掉一档（alpha 0.81 → 0.76）。按比例降下来，近墙的实度
	# 回到原来的样子——挪远是为了构图，不是为了把城变淡。
	material.set_shader_parameter("haze_density", 0.00016)
	material.set_shader_parameter("camera_pos", Vector3.ZERO)
	return material


## 城郭材质：扭得凶、溶解得狠。
##
## 下暗上亮、下暖上冷。
##
## 这是踩出来的：上一版底色是暖沙色（0.90, 0.75, 0.52），而地平线也是
## 亮沙色（0.90, 0.70, 0.45）。同一档颜色叠上去，alpha 0.25 只把背景
## 从 0.90 拉到 0.82——差值 9%，经过 ACES 和暗角之后，**整座城看不见**。
## 幻影再淡也得有对比：底部压到暗褐（贴着沙面的一道暗影），顶上转冷亮
## （像被天空吸走）。这样"下暗上亮"本身就是一条纵深线索。
func _make_city_material() -> ShaderMaterial:
	var material := _base_material("res://shaders/mirage.gdshader")
	material.set_shader_parameter("tint_base", Color(0.34, 0.30, 0.26))
	material.set_shader_parameter("tint_top", Color(0.72, 0.84, 1.00))
	# 折射位移是按 250 m 的观距调出来的；现在观距 1.4 km（5.6 倍），
	# 位移量不跟着放大就完全看不出来了。
	material.set_shader_parameter("shear", CITY_SHEAR)
	material.set_shader_parameter("shear_scale", 1.0)
	# 上缘不做高度淡出：归一化高度要把两座不同高的东西装进同一个刻度，
	# 任何按高度切的一刀都会把其中一个的顶切掉（像头 vs 主塔宝顶）。
	# "看不到顶"由"头顶出画 + 空气衰减"负责，见 mirage.gdshader。
	material.set_shader_parameter("high_fade", 1.0)
	material.set_shader_parameter("haze_tint", Color(0.86, 0.68, 0.47))
	return material


## 像身材质：**几乎不扭、几乎不溶解、颜色压暗**。
##
## 逆光下它要做的事只有一件：当一个能读出来的剪影。
## 上一版它和城郭共用一份材质，于是被 90 m 的横移切成十几段、被 400 m
## 一块的噪声啃出洞、颜色还比背后的天空更亮——三样加起来，一尊 1080 m 的
## 弥勒看起来是一坨带刺的棉花糖。"看不出是弥勒"不是细节不够，是**对比不够**。
func _make_statue_material() -> ShaderMaterial:
	var material := _base_material("res://shaders/mirage.gdshader")
	material.set_shader_parameter("tint_base", Color(0.24, 0.20, 0.17))
	material.set_shader_parameter("tint_top", Color(0.46, 0.53, 0.64))
	material.set_shader_parameter("shear", STATUE_SHEAR)
	material.set_shader_parameter("shear_scale", 1.0)
	# 溶解只留一点点点缀：轮廓必须完整。
	material.set_shader_parameter("dissolve_amount", 0.22)
	# 比城郭实一点：它是这一关里唯一"必须被认出来"的东西。
	material.set_shader_parameter("alpha_scale", 1.75)
	material.set_shader_parameter("brightness", 0.85)
	# 逆光的薄纱也收着：糊过头，剪影就没了。
	material.set_shader_parameter("veil", 0.22)
	material.set_shader_parameter("haze_tint", Color(0.92, 0.74, 0.52))
	material.set_shader_parameter("haze_floor", 0.28)
	return material


## 举身光：加色环，另一支着色器（blend_add）。参数少，见 mirage_halo.gdshader。
func _make_halo_material() -> ShaderMaterial:
	var material := _base_material("res://shaders/mirage_halo.gdshader")
	# 颜色越过 1.0 是有意的：加色环要**顶到 HDR 阈值以上**才会起辉（glow），
	# 而逆光时它背后就是一片过曝的天空——不起辉的话，这圈光等于没画。
	material.set_shader_parameter("halo_color", Color(1.35, 1.10, 0.74))
	# --- 环的径向标尺：几何到哪里、亮带在哪一圈、光焰伸到哪里 ---
	# 三个数都**按当前倍率**算。上一版这里是"几何管子的内径/外径"，
	# 4 倍之后管子跟着长成 302 m 粗的一条带；这一版的"环"是画出来的，
	# 几何只是一枚平的圆环面，粗细由 ring_sigma 决定。
	var h := statue_height()
	# 环心的**本地坐标**：几何在 _design_halo 里按 halo_center 摆，
	# 再由 _xform 统一加上 statue_offset（像身和光环共用一根轴线的那个出口）。
	# 着色器要在盘面上量半径，所以它拿到的必须是加过偏移之后的环心。
	var center := Vector3(h * HALO_BEHIND_RATIO, h * HALO_CENTER_RATIO, 0.0)
	center += statue_offset()
	material.set_shader_parameter("ring_center", Vector2(center.y, center.z))
	material.set_shader_parameter("ring_inner", h * HALO_INNER_RATIO)
	material.set_shader_parameter("ring_core", halo_ring_core())
	material.set_shader_parameter("ring_tip", h * HALO_TIP_RATIO)
	material.set_shader_parameter("ring_sigma", h * HALO_BAND_SIGMA_RATIO)
	# 强度：亮带现在是**一条细的**（σ 0.013h）而不是 0.07h 的管子，
	# 单位面积上的能量集中了，所以比上一版的 2.10 收一档；
	# 留一点余量给光焰和光雾尾巴，它们还要把光摊开。
	material.set_shader_parameter("intensity", 1.25)
	# 光焰：长短不齐、往外的光雾尾巴。见 mirage_halo.gdshader 的那一段注释。
	#
	# 第一版给的 0.34 尾巴在 4 倍尺度上根本看不出来——环干净得像一个圈，
	# 而"有刺才有火"是这个造型从 v3 起就有的设定。现在尾巴 0.55、
	# 衰减指数 1.35，光焰伸得出去；簇数取 26：**不是回到齿轮**——
	# 齿轮的问题是"等长等宽等间隔"，这里每一簇的亮度和长度都由噪声给，
	# 26 簇只是让火舌够细，而不是够齐。
	material.set_shader_parameter("flame_gain", 1.25)
	material.set_shader_parameter("flame_sectors", 26.0)
	material.set_shader_parameter("flame_veil", 0.55)
	material.set_shader_parameter("flame_power", 1.35)
	material.set_shader_parameter("dissolve_amount", 0.40)
	material.set_shader_parameter("flicker", 0.34)
	# 光焰比城郭抗褪：光是会散射的，远处的一圈光不会像砖头那样淡掉。
	material.set_shader_parameter("haze_floor", 0.40)
	material.set_shader_parameter("shear", 14.0)
	return material


func _add_instance(
	name: String, parts: Array[Dictionary], material: Material
) -> void:
	if parts.is_empty():
		return
	_add_mesh_instance(name, _merge_parts(parts), material)


## 挂一个已经成形的 mesh。像身走这条：白膜整份就是一个 mesh，
## 没有"基本体要合并"这件事，也就不该借 SurfaceTool 转一道手。
func _add_mesh_instance(
	name: String,
	mesh: Mesh,
	material: Material,
	offset: Vector3 = Vector3.ZERO,
	scale: float = 1.0
) -> void:
	if mesh == null:
		return
	var instance := MeshInstance3D.new()
	instance.name = name
	instance.mesh = mesh
	instance.material_override = material
	if is_equal_approx(scale, 1.0):
		instance.position = offset
	else:
		# 缩放在平移之前：倍率放大的是像本身，不放大"它站在哪儿"。
		instance.transform = Transform3D(Basis().scaled(Vector3.ONE * scale), offset)
	# 幻影在两公里外，要保证它不会被视锥当成"太远"剔掉
	instance.extra_cull_margin = 400.0
	add_child(instance)


## 读白膜。`.glb` 在 Godot 里导入成 PackedScene，真正的 mesh 挂在它下面
## 某个 MeshInstance3D 上——中间隔着几层节点是导出器的事，不该由调用方去猜，
## 所以这里递归找到第一个 MeshInstance3D。
##
## 找不到就**报错并返回 null**（那样场景里会少一尊像，测试里有一条断言守着）。
## 不做程序化的降级兜底：那等于把"已经删掉的方块像"换个地方留着，
## 出了问题时画面看着"还有东西"，反而更难发现。
func _load_statue_mesh() -> Mesh:
	var packed := load(STATUE_MESH_PATH)
	if packed == null:
		push_error("弥勒白膜缺失：%s" % STATUE_MESH_PATH)
		return null
	var root: Node = (packed as PackedScene).instantiate()
	var found := _first_mesh_instance(root)
	var mesh: Mesh = found.mesh if found != null else null
	if mesh == null:
		push_error("弥勒白膜里没有 mesh：%s" % STATUE_MESH_PATH)
	root.free()
	return mesh


func _first_mesh_instance(node: Node) -> MeshInstance3D:
	var instance := node as MeshInstance3D
	if instance != null and instance.mesh != null:
		return instance
	for child: Node in node.get_children():
		var found := _first_mesh_instance(child)
		if found != null:
			return found
	return null


# ---------------------------------------------------------------------------
# 造型
# ---------------------------------------------------------------------------


func _design() -> void:
	# 主塔：放大 TOWER_SCALE 倍，并整体前移到**城墙后 TOWER_BEHIND_WALL 米**。
	# 塔的造型代码全部按 820 m 高写，乘在变换上而不是乘进上百个常量里——
	# 常量里漏乘一个，轮廓上根本看不出来，只会变成一个悄悄变形的塔。
	_bucket = BUCKET_CITY
	_part_scale = TOWER_SCALE
	_part_offset = Vector3(-CITY_HALF + TOWER_BEHIND_WALL, 0.0, 0.0)
	_design_terraces()
	_design_parapet()
	_design_corner_towers()
	_design_main_body()
	_design_dome()
	_design_finial()

	# 弥勒大像：本身就用真实米写，所以只平移。放在城墙后面 1400 m、
	# 弥勒大像：本身就用真实米写，所以只平移。站在正面城墙**之前**
	# STATUE_FRONT_OF_WALL 米、横向偏到玩家左手边 STATUE_SIDE 米。
	# 只有举身光要在这里拼——像身是外部白膜，由 _ready() 直接挂。
	_bucket = BUCKET_HALO
	_part_scale = 1.0
	_part_offset = statue_offset()
	_design_halo()

	# 城郭：真实米，1:1
	_bucket = BUCKET_CITY
	_part_offset = Vector3.ZERO
	_design_city()


## 五层递收的方台。每层：主体 + 上下线脚 + 四边壁龛 + 四角角柱。
func _design_terraces() -> void:
	for i in range(TIER_WIDTHS.size()):
		var width: float = TIER_WIDTHS[i]
		var height: float = TIER_HEIGHTS[i]
		var base: float = TIER_BASES[i]
		var mid := base + height * 0.5

		_add_box(Vector3(width, height, width), Vector3(0.0, mid, 0.0))

		var lip := width + 14.0
		_add_box(Vector3(lip, 5.0, lip), Vector3(0.0, base + 3.5, 0.0))
		_add_box(Vector3(lip, 5.0, lip), Vector3(0.0, base + height - 3.5, 0.0))

		# 四角角柱：把方台的四个棱描出来，轮廓立刻变"结实"
		var corner := width * 0.5 - 4.0
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				_add_box(
					Vector3(18.0, height + 4.0, 18.0),
					Vector3(sx * corner, mid, sz * corner)
				)

		# 每边一排壁龛：轮廓上的细密锯齿，也是"这是建筑"的最直接证据
		_face_row(
			NICHE_PER_SIDE, width, mid, Vector3(14.0, height * 0.62, 7.0), 0
		)
		_face_row(
			NICHE_PER_SIDE, width, mid, Vector3(14.0, height * 0.62, 7.0), 1
		)


## 台顶栏杆：一圈望柱 + 四面横栏。
func _design_parapet() -> void:
	var rail_y := TERRACE_Y + 20.0
	for i in range(BALUSTRADE_POSTS):
		var t := (float(i) + 0.5) / float(BALUSTRADE_POSTS) * 2.0 - 1.0
		var offset := t * (TERRACE_HALF - 6.0)
		for side: float in [-1.0, 1.0]:
			_add_box(Vector3(9.0, 26.0, 9.0), Vector3(offset, rail_y, side * TERRACE_HALF))
			_add_box(Vector3(9.0, 26.0, 9.0), Vector3(side * TERRACE_HALF, rail_y, offset))

	var rail_len := TERRACE_HALF * 2.0
	for side: float in [-1.0, 1.0]:
		_add_box(
			Vector3(rail_len, 5.0, 7.0), Vector3(0.0, rail_y + 13.0, side * TERRACE_HALF)
		)
		_add_box(
			Vector3(7.0, 5.0, rail_len), Vector3(side * TERRACE_HALF, rail_y + 13.0, 0.0)
		)


func _design_corner_towers() -> void:
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_design_corner_tower(sx * CORNER_TOWER_OFFSET, sz * CORNER_TOWER_OFFSET)


## 四角的小窣堵坡：三层小台基 + 塔身（带壁龛）+ 覆钵 + 莲瓣 + 相轮 + 宝珠。
func _design_corner_tower(px: float, pz: float) -> void:
	var y := TERRACE_Y
	for i in range(3):
		var w := 52.0 - float(i) * 7.0
		_add_box(Vector3(w, 13.0, w), Vector3(px, y + 6.5, pz))
		y += 13.0

	_add_cylinder(23.0, 19.0, 76.0, Vector3(px, y + 38.0, pz), 20)
	for i in range(12):
		var a := TAU * float(i) / 12.0
		_add_box_rot(
			Vector3(8.0, 44.0, 5.0),
			Vector3(px + cos(a) * 22.0, y + 38.0, pz + sin(a) * 22.0),
			Vector3(0.0, -a, 0.0)
		)
	y += 76.0

	_add_sphere(23.0, 54.0, Vector3(px, y + 27.0, pz))
	for i in range(14):
		var a := TAU * float(i) / 14.0
		_add_box_rot(
			Vector3(11.0, 9.0, 6.0),
			Vector3(px + cos(a) * 21.0, y + 12.0, pz + sin(a) * 21.0),
			Vector3(0.0, -a, 0.0)
		)
	y += 54.0

	_add_cylinder(4.0, 4.0, 74.0, Vector3(px, y + 37.0, pz), 8)
	for i in range(7):
		var radius := lerpf(15.0, 7.0, float(i) / 6.0)
		_add_cylinder(radius, radius, 5.0, Vector3(px, y + 12.0 + float(i) * 11.0, pz), 16)
		for j in range(10):
			var a := TAU * float(j) / 10.0
			_add_box(
				Vector3(3.0, 3.0, 3.0),
				Vector3(
					px + cos(a) * radius,
					y + 12.0 + float(i) * 11.0,
					pz + sin(a) * radius
				)
			)
	_add_sphere(8.0, 16.0, Vector3(px, y + 81.0, pz))


## 主塔身：收分圆柱 + 竖壁柱 + 腰线凸块 + 佛龛带。
## 佛龛带是"这是座塔而不是根柱子"的关键——一圈圈规则的小龛，
## 远看就是塔身上连续的横向纹理。
func _design_main_body() -> void:
	_add_cylinder(
		BODY_BOTTOM_R, BODY_TOP_R, BODY_HEIGHT, Vector3(0.0, TERRACE_Y + BODY_HEIGHT * 0.5, 0.0), 48
	)

	# 竖向壁柱：绕塔身一圈，从底到顶
	for i in range(BODY_RIB_COUNT):
		var a := TAU * float(i) / float(BODY_RIB_COUNT)
		var radius := (BODY_BOTTOM_R + BODY_TOP_R) * 0.5 + 1.0
		_add_box_rot(
			Vector3(7.0, BODY_HEIGHT - 6.0, 5.0),
			Vector3(cos(a) * radius, TERRACE_Y + BODY_HEIGHT * 0.5, sin(a) * radius),
			Vector3(0.0, -a, 0.0)
		)

	# 腰线：每道一圈凸块
	for band in range(BODY_BAND_COUNT):
		var t := float(band) / float(BODY_BAND_COUNT - 1)
		var y := TERRACE_Y + 14.0 + t * (BODY_HEIGHT - 28.0)
		var radius := lerpf(BODY_BOTTOM_R, BODY_TOP_R, t) + 3.0
		_add_cylinder(
			radius, radius, 4.0, Vector3(0.0, y, 0.0), 48
		)
		for i in range(BODY_BAND_STUDS):
			var a := TAU * float(i) / float(BODY_BAND_STUDS)
			_add_box(
				Vector3(6.0, 9.0, 6.0),
				Vector3(cos(a) * radius, y, sin(a) * radius)
			)

	# 佛龛带：三圈，每圈两层小龛
	for band in range(SHRINE_BANDS):
		var t := (float(band) + 0.5) / float(SHRINE_BANDS)
		var y := TERRACE_Y + 24.0 + t * (BODY_HEIGHT - 48.0)
		var radius := lerpf(BODY_BOTTOM_R, BODY_TOP_R, t) + 2.0
		for i in range(SHRINE_PER_BAND):
			var a := TAU * float(i) / float(SHRINE_PER_BAND)
			var outward := Vector3(cos(a) * radius, y, sin(a) * radius)
			_add_box_rot(Vector3(11.0, 16.0, 6.0), outward, Vector3(0.0, -a, 0.0))
			_add_box_rot(
				Vector3(13.0, 4.0, 8.0),
				outward + Vector3(cos(a) * 2.0, 10.0, sin(a) * 2.0),
				Vector3(0.0, -a, 0.0)
			)


## 覆钵圆顶 + 一圈莲瓣。
func _design_dome() -> void:
	var dome_base := TERRACE_Y + BODY_HEIGHT
	_add_sphere(DOME_R, DOME_H, Vector3(0.0, dome_base + DOME_H * 0.5, 0.0))
	for i in range(36):
		var a := TAU * float(i) / 36.0
		var radius := DOME_R * 0.62
		_add_box_rot(
			Vector3(14.0, 26.0, 8.0),
			Vector3(cos(a) * radius, dome_base + 10.0, sin(a) * radius),
			Vector3(0.0, -a, 0.0)
		)
	_add_cylinder(30.0, 22.0, 18.0, Vector3(0.0, dome_base + DOME_H - 4.0, 0.0), 24)


## 塔刹：中心柱 + 十三层逐步递减的相轮，每层边缘挂三十二颗珠串 + 华盖。
##
## 相轮是佛塔最有辨识度的剪影，一层都不能省——少几层就从"塔"变成"柱子"。
## 珠串是这一版新加的：它让相轮边缘不再是光滑圆弧，而是毛茸茸的齿。
func _design_finial() -> void:
	var base := TERRACE_Y + BODY_HEIGHT + DOME_H
	_add_cylinder(9.0, 9.0, 236.0, Vector3(0.0, base + 118.0, 0.0), 12)

	for i in range(FINIAL_COUNT):
		var t := float(i) / float(FINIAL_COUNT - 1)
		var radius := lerpf(46.0, 15.0, t)
		var y := base + 26.0 + float(i) * 15.0
		_add_cylinder(radius, radius, 7.0, Vector3(0.0, y, 0.0), 28)
		for j in range(BEADS_PER_RING):
			var a := TAU * float(j) / float(BEADS_PER_RING)
			_add_box(
				Vector3(5.0, 7.0, 5.0),
				Vector3(cos(a) * radius, y, sin(a) * radius)
			)

	# 华盖：一圈下垂的饰件
	var canopy_y := base + 26.0 + float(FINIAL_COUNT - 1) * 15.0 + 26.0
	for i in range(20):
		var a := TAU * float(i) / 20.0
		_add_box_rot(
			Vector3(8.0, 22.0, 6.0),
			Vector3(cos(a) * 26.0, canopy_y, sin(a) * 26.0),
			Vector3(0.0, -a, 0.0)
		)

	_add_sphere(18.0, 36.0, Vector3(0.0, base + 254.0, 0.0))


# ---------------------------------------------------------------------------
# 几何装配
# ---------------------------------------------------------------------------


## 城郭：四面城墙 + 垛口 + 四角楼 + 城门楼 + 城内小塔群与房屋。
##
## 主塔在城中心。城墙把它围起来之后，幻影的轮廓就从"竖着的一根"
## 变成"铺开的一片"——这是"一座城"和"一座塔"的区别所在。
func _design_city() -> void:
	_design_walls()
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_design_bastion(sx * CITY_HALF, sz * CITY_HALF)
	# 城门楼开在**朝玩家那一面**（-CITY_HALF）。上一版开在 +CITY_HALF，
	# 也就是背面的墙上——玩家永远只能从 3.6 km 外看到那座正门。
	_design_gatehouse(-CITY_HALF)
	_design_inner_town()


func _design_walls() -> void:
	var span := CITY_HALF * 2.0
	var mid := WALL_H * 0.5
	# 正面 / 背面（与 X 轴垂直），左 / 右（与 Z 轴垂直）
	_add_box(Vector3(WALL_T, WALL_H, span), Vector3(CITY_HALF, mid, 0.0))
	_add_box(Vector3(WALL_T, WALL_H, span), Vector3(-CITY_HALF, mid, 0.0))
	_add_box(Vector3(span, WALL_H, WALL_T), Vector3(0.0, mid, CITY_HALF))
	_add_box(Vector3(span, WALL_H, WALL_T), Vector3(0.0, mid, -CITY_HALF))

	# 墙基线脚与压顶线：轮廓上的两条横向亮线
	var lip := WALL_T + 26.0
	for sx: float in [-1.0, 1.0]:
		_add_box(Vector3(lip, 16.0, span), Vector3(sx * CITY_HALF, WALL_H - 6.0, 0.0))
		_add_box(Vector3(span, 16.0, lip), Vector3(0.0, WALL_H - 6.0, sx * CITY_HALF))
	for sz: float in [-1.0, 1.0]:
		_add_box(Vector3(lip, 12.0, span), Vector3(sz * CITY_HALF, 8.0, 0.0))
		_add_box(Vector3(span, 12.0, lip), Vector3(0.0, 8.0, sz * CITY_HALF))

	# 垛口：墙顶一排小方块，正面看就是细密的齿
	for i in range(BATTLEMENTS):
		var t := (float(i) + 0.5) / float(BATTLEMENTS) * 2.0 - 1.0
		var offset := t * (CITY_HALF - 24.0)
		var y := WALL_H + 28.0
		for side: float in [-1.0, 1.0]:
			_add_box(Vector3(WALL_T, 56.0, 40.0), Vector3(side * CITY_HALF, y, offset))
			_add_box(Vector3(40.0, 56.0, WALL_T), Vector3(offset, y, side * CITY_HALF))


## 角楼：城墙四角加高的方塔，让轮廓在四个角上立起来。
func _design_bastion(px: float, pz: float) -> void:
	var y := 0.0
	var width := 0.0
	for i in range(BASTION_TIERS.size()):
		width = BASTION_TIERS[i]
		var height := BASTION_H * (1.0 if i == 0 else 0.85)
		_add_box(Vector3(width, height, width), Vector3(px, y + height * 0.5, pz))
		_add_box(
			Vector3(width + 40.0, 26.0, width + 40.0), Vector3(px, y + height - 13.0, pz)
		)
		y += height
	# 攒尖顶：用四棱锥收头
	_add_cylinder(width * 0.5, 12.0, 220.0, Vector3(px, y + 110.0, pz), 4)


## 城门楼：正面中央的制高点，也是幻影里第一个能辨认出"这是建筑"的东西。
##
## 每一段的尺寸都是 GATE_HEIGHT 的比例，总高正好等于 GATE_HEIGHT。
## 上一版这里是写死的米数，加起来 882 m——比 GATE_HEIGHT 写的 900 差不多，
## 但和 620 m 的主塔配在一起就翻了个：**城门楼比主塔还高**，Hierarchy 一乱，
## 巨物就没有"顶点"了，只剩一大片高的东西。
func _design_gatehouse(px: float) -> void:
	var h := GATE_HEIGHT
	# 两座墩台，夹出门洞的位置
	for side: float in [-1.0, 1.0]:
		_add_box(
			Vector3(h * 0.26, h * 0.30, h * 0.26),
			Vector3(px, h * 0.15, side * h * 0.24)
		)
	# 门楣：把两座墩台连成一体，是"门"这个意思的唯一来源
	_add_box(Vector3(h * 0.26, h * 0.15, h * 0.74), Vector3(px, h * 0.375, 0.0))
	# 楼身 + 檐口
	_add_box(Vector3(h * 0.36, h * 0.22, h * 0.60), Vector3(px, h * 0.56, 0.0))
	_add_box(Vector3(h * 0.46, h * 0.03, h * 0.72), Vector3(px, h * 0.685, 0.0))
	# 攒尖顶 + 顶针
	_add_cylinder(h * 0.30, h * 0.03, h * 0.24, Vector3(px, h * 0.82, 0.0), 4)
	_add_cylinder(h * 0.02, h * 0.006, h * 0.06, Vector3(px, h * 0.97, 0.0), 8)
	# 门洞两侧的壁柱
	for side: float in [-1.0, 1.0]:
		_add_box(
			Vector3(h * 0.09, h * 0.30, h * 0.09),
			Vector3(px - h * 0.12, h * 0.15, side * h * 0.24)
		)


## 城内：几座小窣堵坡 + 一片房屋。城市必须"有内容"，
## 否则从城墙后面看过去只是一堵光墙。
##
## 门槛是**城墙高度**：站在 1.4 km 外看，只有高过 400 m 城墙的东西才露得出来。
## 上一版的城内建筑是 46~360 m，全部埋在墙后——那几百个部件一个都看不见。
func _design_inner_town() -> void:
	var shrines := [
		Vector3(-1500.0, 0.0, 1250.0),
		Vector3(-1350.0, 0.0, -1450.0),
		Vector3(1100.0, 0.0, -1300.0),
		Vector3(1500.0, 0.0, 1400.0),
		Vector3(-520.0, 0.0, 1780.0),
		Vector3(430.0, 0.0, -1820.0),
		Vector3(1850.0, 0.0, -280.0),
	]
	for i in range(shrines.size()):
		var position: Vector3 = shrines[i]
		_design_mini_stupa(position.x, position.z, lerpf(700.0, 520.0, float(i) / 6.0))

	# 黄金角散布，避免看出规律。高矮参差才是"一片城"，等高就成了一道墙。
	var tower_x := -CITY_HALF + TOWER_BEHIND_WALL
	for i in range(96):
		var angle := float(i) * 2.39996
		var radius := 380.0 + fmod(float(i) * 173.0, 1700.0)
		var hx := cos(angle) * radius
		var hz := sin(angle) * radius
		# 主塔的台基占地很大，别把房子塞进塔里
		if absf(hx - tower_x) < 420.0 and absf(hz) < 420.0:
			continue
		var height := 300.0 + fmod(float(i) * 53.0, 220.0)
		var width := 200.0 + fmod(float(i) * 31.0, 170.0)
		_add_box(Vector3(width, height, width), Vector3(hx, height * 0.5, hz))
		_add_box(
			Vector3(width + 40.0, 26.0, width + 40.0),
			Vector3(hx, height - 13.0, hz)
		)


# ---------------------------------------------------------------------------
# 弥勒大像
# ---------------------------------------------------------------------------


## 像身在城里的本地位置：站在正面城墙**之前** STATUE_FRONT_OF_WALL 米、
## 横向偏 STATUE_SIDE 米（负 = 玩家左手边，和主塔错开约 23°）。
##
## **只有一个出口**：像身（外部白膜，走读文件那条路）和举身光（程序化环，
## 走 _xform 那条路）是两条完全不同的代码路径，但它们必须落在同一根轴线上。
## 上一版把像身直接挂在节点原点、偏移只写给了 _xform，于是像身在城中心、
## 光环在城墙前——截图里是一枚**空心的发光圆环**。
##
## y 分量是**负的**：`-statue_sink()` 把像身连同举身光一起按进沙面以下，
## 埋掉白膜自带的博物馆台座（见 STATUE_PEDESTAL_RATIO）。放在这里而不是
## 分两处写，是因为像身和光环走的代码路径完全不同——只要有一个地方忘了减，
## 光环就会浮在像的头顶上。
func statue_offset() -> Vector3:
	return Vector3(-CITY_HALF - STATUE_FRONT_OF_WALL, -statue_sink(), STATUE_SIDE)


## 举身光：像身背后那枚**环**。
##
## 像身本身是外部白膜（见文件头那段说明和 STATUE_MESH_PATH），不在这里拼。
## 这里只做它背后的那圈光。
##
## 四版形状的取舍，别改回去：
##   v1 叠一摞圆盘 —— 透明度累加，中心迅速变成一块不透明的实心，不像光；
##   v2 一枚巨大的**实心**盘 —— 盘比像身大，像身就站进了自己的光里。
##      两层半透明白一叠，谁是谁都认不出，这就是"看不出是弥勒"的主因；
##   v3 **环** —— 中间是洞，头、肩、垂手从洞里透出来，光只出现在
##      像身的外沿。于是"人形"和"光"互相成全，而不是互相吃掉。
##   v4（本版）**环的几何只剩一枚平的圆环面** —— 洞还是那个洞（v3 的约束
##      原样保留），但"环有多粗、光焰有多长、边有多软"全部搬进了着色器。
##      为什么要搬：v3 的环是一根 0.07h 粗的 TorusMesh 管子加 28 根等长方条，
##      1 倍时是"一圈光"，**4 倍之后是一条 302 m 宽的亮带加一圈整齐的齿**——
##      形状本身机械，怎么调强度都还是"塑料管"。见 mirage_halo.gdshader。
##
## 为什么"一眼认出这是造像"要靠这圈光：白膜给的是**人**（脸、肚子、如意），
## 光给的是**像**。少了它，那只是一尊巨大的石雕；有了它，才是幻景里逆着光
## 升起来的东西——这一关要的那点佛性就是它。
##
## 环心放在像身轴线**之后** 0.140h：光背要"从背后透出来"，
## 糊在胸口上就变成一块护心镜了。
func _design_halo() -> void:
	# 取"当前"像高而不是设计值：倍率非 1 时环必须跟着一起长，
	# 否则光背会留在脚脖子上。
	var h := statue_height()
	# 这一段加的部件都进"举身光"那个桶（_design() 已经把 _bucket 换好了）：
	# 它用的是加色材质 blend_add，和像身那份混色材质不是一回事。
	var halo_center := Vector3(h * HALO_BEHIND_RATIO, h * HALO_CENTER_RATIO, 0.0)
	# **一枚平的圆环面**：从洞的边缘一直铺到光焰尖。中间的洞是真的洞
	# （像身、头肩、垂手要从洞里透出来——这是从 v3 起就没变过的硬约束）。
	#
	# 形状全部在 fragment 里画（亮带多粗 = ring_sigma、光焰多长 = flame_*、
	# 边多软 = 径向高斯），几何只负责"光能落在哪里"。理由见
	# shaders/mirage_halo.gdshader 的文件头：上一版是"管子 + 28 根等长方条"，
	# 1 倍时还像一圈光，4 倍之后放大成"塑料管套齿轮"。
	_parts_append({
		"mesh": _annulus_mesh(
			h * HALO_INNER_RATIO, h * HALO_TIP_RATIO, HALO_SEGMENTS, HALO_RADIAL_RINGS
		),
		"xform": _xform(halo_center, Vector3.ZERO),
	})
	# 举身光到此为止，后面回城外那一段用的是城郭的桶——_design() 会换回去。


func _design_mini_stupa(px: float, pz: float, height: float) -> void:
	# 每一个尺寸都按 height 成比例：同一座城里混进"瘦针"和"矮墩"，
	# 尺度感立刻就散了。
	var y := 0.0
	_add_box(
		Vector3(height * 0.34, height * 0.07, height * 0.34),
		Vector3(px, height * 0.035, pz)
	)
	y = height * 0.07
	_add_cylinder(
		height * 0.14, height * 0.115, height * 0.42, Vector3(px, y + height * 0.21, pz), 18
	)
	y += height * 0.42
	_add_sphere(height * 0.115, height * 0.26, Vector3(px, y + height * 0.13, pz))
	y += height * 0.26
	_add_cylinder(height * 0.016, height * 0.016, height * 0.24, Vector3(px, y + height * 0.12, pz), 8)
	for i in range(6):
		var radius := lerpf(height * 0.075, height * 0.032, float(i) / 5.0)
		_add_cylinder(
			radius, radius, height * 0.018, Vector3(px, y + height * 0.068 + float(i) * height * 0.040, pz), 14
		)
	_add_sphere(height * 0.032, height * 0.064, Vector3(px, y + height * 0.24 + height * 0.024, pz))


# ---------------------------------------------------------------------------
# 几何装配
# ---------------------------------------------------------------------------


## 沿方台的一对面各排一排小部件。`axis` 0 = 沿 X 排（面朝 ±Z），1 = 沿 Z 排。
func _face_row(count: int, width: float, y: float, size: Vector3, axis: int) -> void:
	var span := width * 0.5 - size.x
	for i in range(count):
		var t := (float(i) + 0.5) / float(count) * 2.0 - 1.0
		var offset := t * span
		var face := width * 0.5
		for side: float in [-1.0, 1.0]:
			if axis == 0:
				_add_box(size, Vector3(offset, y, side * face))
			else:
				_add_box(size, Vector3(side * face, y, offset))


func _add_box(size: Vector3, center: Vector3) -> void:
	_add_box_rot(size, center, Vector3.ZERO)


func _add_box_rot(size: Vector3, center: Vector3, euler: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_parts_append({
		"mesh": mesh,
		"xform": _xform(center, euler),
	})


func _add_cylinder(
	bottom_radius: float,
	top_radius: float,
	height: float,
	center: Vector3,
	segments: int,
	euler := Vector3.ZERO
) -> void:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = bottom_radius
	mesh.top_radius = top_radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	_parts_append({"mesh": mesh, "xform": _xform(center, euler)})


func _add_sphere(radius: float, height: float, center: Vector3) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 20
	mesh.rings = 10
	_parts_append({"mesh": mesh, "xform": _xform(center, Vector3.ZERO)})


## 一枚**平的圆环面**（annulus）：内半径 r_inner、外半径 r_outer，
## 躺在 YZ 平面上（轴顺着 X），所以它正对着玩家——玩家在像身的 -X 侧。
##
## 为什么不用 `TorusMesh`：Godot 的圆环躺在 XZ 平面上（轴是 Y），要用就得
## 转 90°，而且它**有管壁厚度**——举身光要的是一枚没有厚度的面，形状全靠
## 着色器画（见 mirage_halo.gdshader）。厚度来自几何，就一定会被放大成
## "一圈塑料管"。自己拼一个环面，厚度这件事从几何里彻底消失。
##
## 径向分 `rings + 1` 层：面本身是平的，多分几层是为了让顶点的**折射位移**
## 有径向分辨率——只有内外两圈顶点的话，噪声位移会被拉成一条扭转的带子。
func _annulus_mesh(r_inner: float, r_outer: float, segments: int, rings: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for j in range(rings + 1):
		var t := float(j) / float(rings)
		var r := lerpf(r_inner, r_outer, t)
		for i in range(segments + 1):
			var a := TAU * float(i) / float(segments)
			verts.append(Vector3(0.0, cos(a) * r, sin(a) * r))
			# 法线顺着 -X（朝向玩家）。cull_disabled + 着色器里取绝对值，
			# 所以背面也照常亮，法线不必逐面翻。
			norms.append(Vector3(-1.0, 0.0, 0.0))
			uvs.append(Vector2(float(i) / float(segments), t))
	for j in range(rings):
		for i in range(segments):
			var b := j * (segments + 1) + i
			var c := b + segments + 1
			indices.append_array([b, c, b + 1, b + 1, c, c + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## 部件按材质分桶（城郭 / 像身 / 举身光），造型代码不需要知道这件事。
func _parts_append(part: Dictionary) -> void:
	match _bucket:
		BUCKET_HALO:
			_parts_halo.append(part)
		_:
			_parts.append(part)


## 部件的局部变换：绕自身旋转 → 整体缩放 → 整体平移。
## 缩放在平移之前，所以 _part_offset 是"塔基落在城里的位置"，不受倍率影响。
func _xform(center: Vector3, euler: Vector3) -> Transform3D:
	var basis := Basis.from_euler(euler)
	if not is_equal_approx(_part_scale, 1.0):
		basis = basis.scaled(Vector3.ONE * _part_scale)
	return Transform3D(basis, center * _part_scale + _part_offset)


## 把一个桶里的基本体合成一个 mesh。
##
## 分开挂两千个 MeshInstance3D 就是两千次绘制调用，换一个两公里外、
## 半透明、还看不清的东西——没有道理。合并之后是一次绘制。
func _merge_parts(parts: Array[Dictionary]) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part: Dictionary in parts:
		tool.append_from(part["mesh"], 0, part["xform"])
	return tool.commit()


func part_count() -> int:
	return _parts.size() + _parts_halo.size()


# ---------------------------------------------------------------------------
# 表现
# ---------------------------------------------------------------------------


## 0..1：越接近 1，幻影越实。驱动它的是"渴"和"沙暴"，不是时间表。
func set_presence(value: float) -> void:
	presence = clampf(value, 0.0, 1.0)
	var shown := presence > 0.02
	visible = shown
	if shown:
		# 空气衰减先砍掉三成（1.4 km 处透射 0.72），溶解项再砍一成，
		# 所以 strength 要乘 2.0：presence=0.29 时近墙的实心部分约 0.38，
		# 是"沙尘里一道压得住画面的暗影"；渴到见底（presence→1）时 1.0，
		# 整座城几乎凝实——**幻影的浓淡就是玄奘还剩多少水**。
		_material.set_shader_parameter("strength", presence * 2.0)
		# 像身和举身光跟着同一股"渴"走，但各自有各自的缩放：
		# 像身要更实（它得被认出来），光背衰减得更慢（光是会散射的）。
		if _statue_material != null:
			_statue_material.set_shader_parameter("strength", presence * 2.0)
			_statue_material.set_shader_parameter("shimmer", lerpf(4.0, 1.5, presence))
		if _halo_material != null:
			_halo_material.set_shader_parameter("strength", presence * 2.4)
		# 越淡的幻影扭得越厉害：快要散掉的东西才晃得凶
		_material.set_shader_parameter("shimmer", lerpf(26.0, 7.0, presence))


## 每帧告诉幻影"相机在哪"。
##
## 它的材质关掉 Godot 的雾（fog_disabled），所以空气衰减必须自己算，
## 而自己算就需要知道观察点的位置。相机位置只走这一个入口，
## 免得 shader 里再去猜 CAMERA_POSITION_WORLD 这类版本相关的东西。
func set_camera_position(value: Vector3) -> void:
	if _material != null:
		_material.set_shader_parameter("camera_pos", value)
	if _statue_material != null:
		_statue_material.set_shader_parameter("camera_pos", value)
	if _halo_material != null:
		_halo_material.set_shader_parameter("camera_pos", value)


## 告诉幻影"太阳在哪"，逆光薄纱和光背的加亮都靠它。
##
## 只走这一个入口：太阳是**世界**的属性（DesertWorld 算），幻影只消费。
## 幻影自己的材质关着 Godot 的雾，所以它也没法从引擎那里蹭到这个方向。
func set_sun_direction(value: Vector3) -> void:
	var direction := value.normalized()
	if _material != null:
		_material.set_shader_parameter("sun_direction", direction)
	if _statue_material != null:
		_statue_material.set_shader_parameter("sun_direction", direction)
	if _halo_material != null:
		_halo_material.set_shader_parameter("sun_direction", direction)


## 让幻影极缓慢地上下浮动，像隔着热空气在看。
func drift(time: float) -> void:
	position.y = _base_y + sin(time * 0.17) * 7.0


var base_y := 0.0:
	set(value):
		_base_y = value
		position.y = value
	get:
		return _base_y
