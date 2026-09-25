# 背景音乐：从网易云 ncm 到游戏里的一首循环曲

写这份文档的原因和 [asset-sourcing.md](asset-sourcing.md) 一样：**下一次还要干这件事**。
2026-09-24 把《壁上观》(DeathNov Remix 剪辑版）放进这一关，从 ncm 解包到
确认"整曲循环接得上"，中间有几件事值得记下来。

---

## 0. 一页结论

| 项 | 值 |
|---|---|
| 源 | `E:\CloudMusic\VipSongsDownload\DeathNov朱文杰 - 壁上观 (Deathnov Remix 剪辑版）.ncm` |
| 转换工具 | <https://github.com/lemonhall/ncmTran_mac>（`tr.py`） |
| 产物 | `assets/audio/bgm/bishangguan-deathnov-remix.mp3`，2 963 666 B |
| 格式 | MPEG-1 Layer III、320 kbps、44.1 kHz、立体声、**74.0 s** |
| 循环 | `.import` 里 `loop=true`，整曲循环 |
| 玩法耦合 | **零**。不跟沙暴变调、不跟渴度变响、不做总线滤波 |

## 1. 转换：一条命令，但有两个坑

`tr.py` 的用法是"给一个目录，它把目录里所有 .ncm 转掉"。所以先在
`_agent_tmp` 下建一个空目录，把要转的那一个 .ncm **改名后拷进去**再跑：

```powershell
python E:\development\ncmTran_mac\tr.py <暂存目录>
```

两个坑：

1. **它会转掉整个目录。** 源目录里还有另一首 ncm（品冠《雨过天晴》）。
   直接指向 `VipSongsDownload` 就会把别人不想动的东西一起转出来。
   用"单文件暂存目录"这个习惯动作，比给工具加过滤参数省事。
2. **文件名里的全角括号会咬人。** 原名是
   `DeathNov朱文杰 - 壁上观 (Deathnov Remix 剪辑版）.ncm`——为了把输出名定下来，
   先把它拷成 `bishangguan-deathnov-remix.ncm`（`tr.py` 的输出名 = 输入名换个后缀）。
   顺便也就把"中文 + 全角符号"从后续所有命令行里清出去了。

`tr.py` 还会顺手去网易的 CDN 抓专辑封面（`albumPic`），并把原曲的 ID3 标签写进 mp3。
封面是 155 KB 的 jpg，游戏用不上，留在暂存目录没入库。

## 2. 目录里放的是 mp3，循环是素材自己的属性

Godot 的 mp3 导入参数里有 `loop`。它写在 `assets/audio/bgm/*.mp3.import` 里，
**不在代码里改**：

```ini
[params]
loop=true
loop_offset=0
```

理由：`load()` 拿到的是资源缓存里那一份，运行时写 `stream.loop = true`
等于改了一个全局共享对象——谁先跑谁定调，这种隐式状态最难查。素材属性放素材文件里，
测试直接断言 `track.loop`，一旦导入参数丢了立刻红。

## 3. 为什么敢整曲循环：先量首尾电平

"剪辑版"多半是硬切的，硬切接硬切会"啪"一声。所以在接上之前先用 ffmpeg 量一遍：

```powershell
ffmpeg -hide_banner -i <mp3> -af volumedetect -f null -            # 整曲
ffmpeg -hide_banner -i <mp3> -af "atrim=0:0.4,volumedetect" -f null -      # 开头
ffmpeg -hide_banner -sseof -0.4 -i <mp3> -af volumedetect -f null -         # 尾巴
```

实测：

| 段 | mean_volume |
|---|---|
| 整曲 | -9.9 dB（max 0.0 dB，母带做满了） |
| 开头 0.4 s | **-91.0 dB ≈ 数字静音** |
| 0.4–1.4 s | -45.0 dB（从静音里起拍） |
| 结尾 69–70 / 70–71 / 71–72 / 72–73 / 73–74 s | -24.7 → -30.0 → -34.1 → -38.5 → **-43.9 dB** |

尾巴是一条平滑淡出、落在 -44 dB，开头是 0.4 s 的数字静音后从 -45 dB 起拍——
**两头在同一个电平量级上接上了**，不需要裁剪、不需要交叉淡化。

两件顺带的事：

- 母带峰值 0 dB，所以 `VOLUME_DB` 基准压到 **-6 dB**，给后处理的高光留余量。
- 时长 74 s 写进测试断言（60~90 s 区间）：既挡住"文件是空的"，也挡住哪天误换了别的音频。

## 4. 它不掺状态（这是被明确要求过的取舍）

第一版写了一整套"沙暴越强越闷、幻影越清越亮、水尽则静音"的混音逻辑——独立
`Music` 总线 + 低通 + 三条曲线 + 幂等建总线。柠檬叔的判词是：

> 你那啥别弄这么复杂，就是一个BGM，还弄一堆状态机啥的。。。就一直给我播放就好了啊

于是删干净了，只剩载入 / 循环 / 播放三件事。**记在这里，别再加回来。**
氛围的底子应该稳；要调大小就改 `VOLUME_DB` 那一个常量。

**风声不算"加回来"**（2026-09-24）：`scripts/audio/wind.gd` 是**另一条独立的层**，
它读 `GameState.wind_force`、跟着风起风落，但那是它自己的录音机，不是这首曲子的
状态机——音乐这一条仍然是"载入 / 循环 / 播放"。分界线是：**曲子不许因为
世界上发生了什么而变形**；一个会随世界变化的音效，应该另起一个播放器。
风声的基准压到 `BASE_DB = -12 dB`（在音乐的 -6 dB 之下），闭眼时和喘气一起退场。

## 5. 别把 headless 的收尾告警当成失败

`godot --headless tests/test_scene.tscn` 退出时会打印：

```
WARNING: 2 ObjectDB instances were leaked at exit
ERROR: 1 resources still in use at exit
```

它指的是那枚 `AudioStreamMP3` 和它的 playback。**最小复现是不跑任何测试、
只跑 `scenes/main.tscn`**——一样报，而且多等 10 秒也不消失：headless 下没有
音频设备，播放实例停在混音器的待释放队列里，直到进程退出也没人处理它。
这是收尾路径的问题，不是这一关漏了什么。判定仍看 `ALL TESTS PASSED`。

（顺带记一条真会咬人的：`AudioStreamPlayer` 节点如果被 `queue_free()` 但又没等到
帧末真正析构，混音器上会留着活的播放实例。所以测试里拆场景用 `free()`
而不是 `queue_free()`。）

## 6. Web 上这首歌交给**浏览器**播，不进 Godot 的混音器

这是 2026-09-24 修"音乐被拖慢"那一格时的取舍，**别改成 Stream**。

桌面上混音器有自己的线程，Stream 播放原生循环、内存也小，所以桌面维持原样。
Web 不是：4.7 的 `platform/web/audio_driver_web.cpp` 在不开 Thread Support 时，
混音就在**主线程**上跑（`_process_callback` → `audio_server_process`，每 128 帧
一个 render quantum，靠 AudioWorklet 的 postMessage 往返供数据）。渲染一忙，
先喂不上，worklet 就丢掉那个 quantum。丢一个 quantum 是 2.7 ms 的静音，
丢得密了听感就是**被拖慢**——像磁带被人按住。这不是缓冲大小问题，是
"把音乐放在了和渲染抢同一条线程上"。

`Bgm` 因此在 Web 上显式设 `playback_type = AudioServer.PLAYBACK_TYPE_SAMPLE`：
引擎会把整条流**预先混一遍**成 PCM（`register_sample` → `godot_audio_sample_register_stream`），
交给浏览器原生的 `AudioBufferSourceNode` 播放。

* 解码/预混只在**加载时一次**（74 s 立体声 ≈ 26 MB 的 AudioBuffer）——
  正好落在加载页那几秒里，播放期间主线程一次都不插手；
* 于是"音乐被渲染拖慢"结构上不可能发生；
* 代价：**循环由 JS 在 `ended` 事件里重启**（不是原生 loop），接缝比桌面明显一点。
  这首歌头尾本来就有 0.4 s 静音和一条 -24.7 → -43.9 dB 的淡出，接得住——
  第 3 节量的那两个数，在这里又多赚了一次。

喘气和风声不能这么做：它们是 `AudioStreamGenerator` 现场合成，sample 播放
要求整条流能预先解成 AudioBuffer，生成器给不出来，引擎会直接丢掉这条流
（只留一句 "trying to play a sample from a stream that cannot be sampled"）。
所以那两个显式设成 `PLAYBACK_TYPE_STREAM`，留在混音器上，靠
`audio/driver/output_latency.web=100`（默认 50，缓冲 2048 → 4096 帧 ≈ 42.7 → 85.3 ms）
撑余量。

实测（有头 Chrome，24 秒连续行走，输出波形用 `AnalyserNode` 抓）：
改之前 24 秒里最长纯静音段 384 样本（丢了一个 quantum），改之后 **0**；
`createBufferSource` 从 0 变 1；BGM 播放速率两版都是 1.0000×。
