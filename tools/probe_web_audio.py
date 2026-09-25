"""Probe the web build's audio path in a real browser session.

Usage: python tools/probe_web_audio.py <url> <out-dir> [width height] [--headed]
                                          [--bgm=<path to the mp3>]

What it measures, and why each number matters:

  * context / worklet / driver log      — is the AudioWorklet path even alive
  * createBufferSource() count          — sample playback (browser-native) evidence:
                                          the BGM taking that route means Godot's
                                          main-thread mixer is not playing it
  * output tap (AnalyserNode on the     — the *actual* waveform: RMS (is there
    node feeding ctx.destination)         sound), peak (clipping), and zero-run
                                          stats. A dropped render quantum is
                                          digital silence, so "longest run of
                                          exact zeros" is a dropout detector.
  * rAF frame deltas                    — main-thread load, to correlate with the
                                          dropout counts
"""

import json
import sys
from pathlib import Path

from playwright.sync_api import sync_playwright

INIT = """
window.__audio = { log: [], ctx: null, bufferSources: 0, buckets: {}, analyser: null };
(function () {
  const RealAC = window.AudioContext;
  function makeRecorder(ctx) {
    if (window.__audio.analyser) { return; }
    const analyser = ctx.createAnalyser();
    analyser.fftSize = 2048;
    window.__audio.analyser = analyser;
    const mute = ctx.createGain();
    mute.gain.value = 0;
    window.__audio.mute = mute;
    const connect = AudioNode.prototype.connect;
    connect.call(analyser, mute);
    connect.call(mute, ctx.destination);
    window.__audio.log.push('tap: analyser attached to destination feed');
  }
  window.AudioContext = function (...args) {
    const ctx = new RealAC(...args);
    window.__audio.ctx = ctx;
    window.__audio.log.push('ctx created, state=' + ctx.state + ', sampleRate=' + ctx.sampleRate);
    const onstate = ctx.onstatechange;
    ctx.onstatechange = function (ev) {
      window.__audio.log.push('onstatechange -> ' + ctx.state);
      if (onstate) { onstate.call(ctx, ev); }
    };
    const resume = ctx.resume.bind(ctx);
    ctx.resume = function () {
      const p = resume();
      p.then(() => window.__audio.log.push('resume ok, state=' + ctx.state))
       .catch((e) => window.__audio.log.push('resume failed: ' + e));
      return p;
    };
    const addModule = ctx.audioWorklet.addModule.bind(ctx.audioWorklet);
    ctx.audioWorklet.addModule = function (url) {
      window.__audio.log.push('addModule ' + url);
      const p = addModule(url);
      p.then(() => window.__audio.log.push('addModule ok'))
       .catch((e) => window.__audio.log.push('addModule failed: ' + e));
      return p;
    };
    const cbs = ctx.createBufferSource.bind(ctx);
    ctx.createBufferSource = function () {
      window.__audio.bufferSources += 1;
      return cbs();
    };
    const connect = AudioNode.prototype.connect;
    AudioNode.prototype.connect = function (dest, ...rest) {
      if (dest === ctx.destination && this !== window.__audio.mute
          && this !== window.__audio.analyser) {
        makeRecorder(ctx);
        if (window.__audio.analyser && this !== window.__audio.analyser) {
          window.__audio.log.push('connect -> destination tapped (' + this.constructor.name + ')');
          connect.call(this, window.__audio.analyser);
        }
      }
      return connect.call(this, dest, ...rest);
    };
    return ctx;
  };
  window.AudioContext.prototype = RealAC.prototype;
})();
window.__audioStart = function () {
  const a = window.__audio;
  a.buckets = {};
  a.running = true;
  let last = performance.now();
  let prevTail = null;
  function tick(now) {
    const delta = now - last;
    last = now;
    const bucketKey = Math.floor(now / 50);
    let b = a.buckets[bucketKey];
    if (!b) {
      b = { n: 0, frameSum: 0, frameMax: 0, polls: 0, zeroRunMax: 0, zeros: 0, samples: 0,
            rmsSum: 0, peak: 0, stepMax: 0, silencePolls: 0, repeatPolls: 0 };
      a.buckets[bucketKey] = b;
    }
    b.n += 1;
    b.frameSum += delta;
    if (delta > b.frameMax) { b.frameMax = delta; }
    const an = a.analyser;
    if (an) {
      const buf = new Float32Array(an.fftSize);
      an.getFloatTimeDomainData(buf);
      let e = 0, peak = 0, zeros = 0, run = 0, runMax = 0, step = 0;
      let lastV = prevTail === null ? buf[0] : prevTail;
      for (const v of buf) {
        e += v * v;
        const av = v < 0 ? -v : v;
        if (av > peak) { peak = av; }
        const s = Math.abs(v - lastV);
        if (s > step) { step = s; }
        lastV = v;
        if (v === 0) { zeros += 1; run += 1; if (run > runMax) { runMax = run; } } else { run = 0; }
      }
      prevTail = buf[buf.length - 1];
      const rms = Math.sqrt(e / buf.length);
      b.polls += 1;
      b.samples += buf.length;
      b.rmsSum += rms;
      b.zeros += zeros;
      if (runMax > b.zeroRunMax) { b.zeroRunMax = runMax; }
      if (peak > b.peak) { b.peak = peak; }
      if (step > b.stepMax) { b.stepMax = step; }
      if (rms < 0.005) { b.silencePolls += 1; }
    }
    if (a.running) { requestAnimationFrame(tick); }
  }
  requestAnimationFrame(tick);
};
window.__audioStop = function () {
  window.__audio.running = false;
  return { buckets: window.__audio.buckets, samples: window.__audio.ctx.sampleRate };
};
"""


def bgm_envelope(path, rate=8000, bin_ms=50):
    """RMS envelope of a reference audio file, in `bin_ms` buckets."""
    import subprocess

    raw = subprocess.run(
        ["C:\\ProgramData\\chocolatey\\bin\\ffmpeg.exe", "-v", "error", "-i", str(path),
         "-ac", "1", "-ar", str(rate), "-f", "s16le", "-"],
        capture_output=True, check=True,
    ).stdout
    step = rate * bin_ms // 1000
    out = []
    for start in range(0, len(raw) - 2 * step, step):
        chunk = raw[start * 2:(start + step) * 2]
        total = 0
        for i in range(0, len(chunk), 2):
            v = int.from_bytes(chunk[i:i + 2], "little", signed=True) / 32768.0
            total += v * v
        out.append((total / max(step, 1)) ** 0.5)
    return out


def _corr(a, b):
    ma = sum(a) / len(a)
    mb = sum(b) / len(b)
    num = sum((x - ma) * (y - mb) for x, y in zip(a, b))
    da = sum((x - ma) ** 2 for x in a) ** 0.5
    db = sum((y - mb) ** 2 for y in b) ** 0.5
    if da == 0 or db == 0:
        return 0.0
    return num / (da * db)


def drift_rate(series, reference, span_buckets=120):
    """How fast the output walks through the reference, in reference-buckets per
    output-bucket. 1.0 = real time, < 1.0 = the music is being dragged."""
    if len(series) < span_buckets * 2 + 4 or len(reference) < span_buckets + 2:
        return None
    first = series[1:1 + span_buckets]
    last = series[-span_buckets - 1:-1]
    best_a, score_a = 0, -2.0
    for off in range(0, len(reference) - span_buckets):
        s = _corr(first, reference[off:off + span_buckets])
        if s > score_a:
            best_a, score_a = off, s
    expected = best_a + (len(series) - 1 - span_buckets - 1)
    lo = max(0, expected - 120)
    hi = min(len(reference) - span_buckets, expected + 120)
    best_b, score_b = lo, -2.0
    for off in range(lo, hi):
        s = _corr(last, reference[off:off + span_buckets])
        if s > score_b:
            best_b, score_b = off, s
    gap_buckets = len(series) - span_buckets - 1 - 1
    if gap_buckets <= 0:
        return None
    return {
        "rate": (best_b - best_a) / gap_buckets,
        "corr_start": round(score_a, 3),
        "corr_end": round(score_b, 3),
        "offset_start_s": round(best_a * 0.05, 2),
        "offset_end_s": round(best_b * 0.05, 2),
        "gap_s": round(gap_buckets * 0.05, 2),
    }


def summarize(buckets):
    if not buckets:
        return None
    series = buckets.values() if isinstance(buckets, dict) else buckets
    frames = [b["n"] for b in series]
    deltas = [b["frameSum"] / b["n"] for b in series if b["n"]]
    deltas_sorted = sorted(deltas)
    polls = [b["polls"] for b in series]
    zero_run = [b["zeroRunMax"] for b in series]
    zeros = [b["zeros"] / b["samples"] if b["samples"] else 0 for b in series]
    rms = [b["rmsSum"] / b["polls"] if b["polls"] else 0 for b in series]
    peak = [b["peak"] for b in series]
    silence = [b["silencePolls"] for b in series]
    all_frames = sum(frames)
    total_seconds = len(buckets) * 0.05
    return {
        "buckets": len(buckets),
        "seconds": round(total_seconds, 1),
        "fps": round(all_frames / total_seconds, 1) if total_seconds else None,
        "frame_mean_ms": round(sum(deltas) / len(deltas), 2),
        "frame_p95_ms": round(deltas_sorted[int(len(deltas_sorted) * 0.95)], 2),
        "frame_max_ms": round(max(deltas), 2),
        "polls_total": sum(polls),
        "zero_run_max": max(zero_run),
        "buckets_with_zero_run_ge_64": sum(1 for z in zero_run if z >= 64),
        "buckets_with_zero_run_ge_256": sum(1 for z in zero_run if z >= 256),
        "zero_fraction_mean": round(sum(zeros) / len(zeros), 5),
        "rms_mean": round(sum(rms) / len(rms), 4),
        "rms_min": round(min(rms), 4),
        "peak": round(max(peak), 4),
        "silent_buckets": sum(1 for s in silence if s > 0),
    }


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    headed = "--headed" in sys.argv
    url, out_dir = args[0], Path(args[1])
    width = int(args[2]) if len(args) > 2 else 960
    height = int(args[3]) if len(args) > 3 else 540
    bgm_path = None
    for a in sys.argv[1:]:
        if a.startswith("--bgm="):
            bgm_path = Path(a.split("=", 1)[1])
    out_dir.mkdir(parents=True, exist_ok=True)
    console = []
    with sync_playwright() as p:
        browser = p.chromium.launch(
            channel="chrome",
            headless=not headed,
            args=["--no-sandbox", "--autoplay-policy=document-user-activation-required"]
            + ([] if headed else ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"]),
        )
        page = browser.new_page(viewport={"width": width, "height": height})
        page.set_default_timeout(240000)
        page.add_init_script(INIT)
        page.on("console", lambda m: console.append("%s: %s" % (m.type, m.text)))
        page.on("pageerror", lambda e: console.append("pageerror: %s" % e))
        page.goto(url, wait_until="load")
        started = False
        for _ in range(60):
            page.wait_for_timeout(2000)
            if page.evaluate("() => !document.getElementById('status')"):
                started = True
                break
        page.bring_to_front()
        lock = None
        for _ in range(3):
            page.mouse.click(width // 2, height // 2)
            page.wait_for_timeout(1500)
            lock = page.evaluate(
                "() => document.pointerLockElement ? document.pointerLockElement.id : null"
            )
            if lock:
                break
        page.wait_for_timeout(3000)

        def measure(label, seconds, walk):
            page.evaluate("() => window.__audioStop()")
            if walk:
                page.keyboard.down("w")
            page.evaluate("() => window.__audioStart()")
            page.wait_for_timeout(int(seconds * 1000))
            payload = page.evaluate("() => window.__audioStop()")
            if walk:
                page.keyboard.up("w")
            raw = payload["buckets"]
            buckets = {int(k): v for k, v in raw.items()}
            stats = summarize(buckets)
            # 时间轴必须是均匀的：rAF 若在某个 50 ms 桶里一次都没跑（主线程卡住），
            # 那个桶就是"没采到"，但音频照样在播。缺桶用相邻值填上，
            # 否则 drift 的时间轴会被隐形压缩，量出来的速率是假的。
            keys = sorted(buckets)
            filled = {}
            for k in range(keys[0], keys[-1] + 1):
                b = buckets.get(k)
                filled[k] = (b["rmsSum"] / b["polls"]) if b and b["polls"] else None
            series = []
            fallback = 0.0
            for k in range(keys[0], keys[-1] + 1):
                v = filled[k]
                if v is None:
                    v = fallback
                series.append(v)
                fallback = v
            print(
                "  %-8s fps=%s frame mean=%.1f p95=%.1f max=%.1f ms | rms=%.4f min=%.4f "
                "peak=%.3f | zeroRunMax=%d buckets>=64:%d >=256:%d | zeroFrac=%.5f"
                % (
                    label, stats["fps"], stats["frame_mean_ms"], stats["frame_p95_ms"],
                    stats["frame_max_ms"], stats["rms_mean"], stats["rms_min"], stats["peak"],
                    stats["zero_run_max"], stats["buckets_with_zero_run_ge_64"],
                    stats["buckets_with_zero_run_ge_256"], stats["zero_fraction_mean"],
                )
            )
            return stats, series

        print("engine started:", started, "| pointer lock:", lock)
        idle, _ = measure("idle", 6, False)
        # 小步移动鼠标：同时抓 [鼠标诊断] 的 relative，验证"轻轻一动就顶到穹顶"。
        for i in range(6):
            page.mouse.move(width // 2 + 3 * (i + 1), height // 2 + (i % 2))
            page.wait_for_timeout(120)
        walk, walk_series = measure("walking", 24, True)
        drift = None
        if bgm_path is not None and bgm_path.exists():
            drift = drift_rate(walk_series, bgm_envelope(bgm_path))
            if drift:
                print(
                    "  drift    BGM 播放速率 = %.4f x 实时（1.00 正常，<0.99 被拖慢）"
                    "  窗口内走了 %.2f s / 墙钟 %.2f s  相关度 %.3f / %.3f"
                    % (drift["rate"], drift["offset_end_s"] - drift["offset_start_s"],
                       drift["gap_s"], drift["corr_start"], drift["corr_end"])
                )
            else:
                print("  drift    样本不足，跳过")
        page.wait_for_timeout(500)
        state = page.evaluate(
            """() => ({
                 log: window.__audio.log,
                 ctxState: window.__audio.ctx ? window.__audio.ctx.state : 'no context',
                 sampleRate: window.__audio.ctx ? window.__audio.ctx.sampleRate : null,
                 bufferSources: window.__audio.bufferSources,
                 pointerLock: document.pointerLockElement ? document.pointerLockElement.id : null,
               })"""
        )
        page.screenshot(path=str(out_dir / "probe2.png"), timeout=240000)
        browser.close()
    payload = {
        "started": started,
        "state": state,
        "idle": idle,
        "walking": walk,
        "drift": drift,
        "console": console,
    }
    (out_dir / "probe2.json").write_text(json.dumps(payload, indent=2), encoding="utf-8")
    print("context:", state.get("ctxState"), state.get("sampleRate"), "ctx")
    print("createBufferSource calls:", state.get("bufferSources"))
    for line in state.get("log", []):
        print("  audio:", line)
    marks = ("[鼠标诊断]", "[首帧信号]", "cannot be sampled", "driver", "AudioWorklet",
             "pageerror", "error")
    for line in console:
        if any(mark in line for mark in marks):
            print("  console:", line)


if __name__ == "__main__":
    main()
