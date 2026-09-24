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
