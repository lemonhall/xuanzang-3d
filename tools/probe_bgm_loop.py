"""Does the BGM actually loop on the web sample path? (74 s track, run 170 s.)

The web sample path restarts on the AudioBufferSourceNode's `ended` event instead
of looping natively, so "the music stops after 74 s" is a real failure mode.
Watch: RMS (kept alive), the source count (a restart makes a new one),
and the longest silent gap.
"""

import sys
from pathlib import Path

from playwright.sync_api import sync_playwright

from probe_web_audio import INIT


def main() -> None:
    url = sys.argv[1]
    seconds = float(sys.argv[2]) if len(sys.argv) > 2 else 170.0
    console = []
    with sync_playwright() as p:
        browser = p.chromium.launch(
            channel="chrome", headless=False,
            args=["--no-sandbox", "--autoplay-policy=document-user-activation-required"],
        )
        page = browser.new_page(viewport={"width": 960, "height": 540})
        page.set_default_timeout(240000)
        page.add_init_script(INIT)
        page.on("console", lambda m: console.append("%s: %s" % (m.type, m.text)))
        page.goto(url, wait_until="load")
        for _ in range(60):
            page.wait_for_timeout(2000)
            if page.evaluate("() => !document.getElementById('status')"):
                break
        page.bring_to_front()
        page.mouse.click(480, 270)
        page.wait_for_timeout(2000)
        page.keyboard.down("w")
        print("%6s %10s %14s %10s" % ("t(s)", "src count", "rms", "ctx"))
        samples = []
        t = 0.0
        while t < seconds:
            page.wait_for_timeout(3000)
            t += 3.0
            row = page.evaluate(
                """() => {
                  const a = window.__audio.analyser;
                  let rms = 0;
                  if (a) {
                    const buf = new Float32Array(a.fftSize);
                    a.getFloatTimeDomainData(buf);
                    let e = 0;
                    for (const v of buf) { e += v * v; }
                    rms = Math.sqrt(e / buf.length);
                  }
                  return { rms, src: window.__audio.bufferSources,
                           ctx: window.__audio.ctx ? window.__audio.ctx.state : 'none' };
                }"""
            )
            samples.append((t, row["rms"], row["src"]))
            print("%6.0f %10d %14.4f %10s" % (t, row["src"], row["rms"], row["ctx"]))
        page.keyboard.up("w")
        browser.close()
    silences = [t for t, rms, _ in samples if rms < 0.01]
    longest = 0
    run = 0
    for index, _ in enumerate(samples):
        run = run + 1 if samples[index][0] in silences else 0
        longest = max(longest, run)
    print()
    print("最长连续静音：%d 个采样点（每个 3 s）；静音点 %d / %d"
          % (longest, len(silences), len(samples)))
    print("AudioBufferSource 数量变化：%d → %d（每过一次循环边界 +1）"
          % (samples[0][2], samples[-1][2]))
    for line in console:
        if "error" in line.lower() or "pointer" in line.lower():
            print("  console:", line)


if __name__ == "__main__":
    main()
