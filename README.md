# MacSlap 💥

**Hit your MacBook and it screams *AUUGHHH*.**

MacSlap uses the motion sensor that Apple puts inside Apple Silicon MacBooks but doesn't document. When you slap or knock the body of your laptop, it plays the sound in full. Loud noises, music and normal typing don't set it off, because it reacts to the physical hit, not to sound.

---

## ✅ Requirements

| | |
|---|---|
| **Mac** | MacBook Air / Pro with an **M2, M3, M4 or M5** chip |
| **Not supported** | M1 MacBooks, Intel Macs, iMac, Mac mini, Mac Studio (no sensor) |
| **macOS** | 13 Ventura or newer |
| **Tools** | Swift (included with Xcode or the free Command Line Tools) |
| **Permissions** | Your Mac password (`sudo`). Reading the sensor needs admin rights |

Not sure which chip you have? Go to  menu → **About This Mac**.

---

## 🚀 Quick start

Open **Terminal** and run:

```bash
git clone https://github.com/navid39-swift/MacSlap.git
cd MacSlap
./run.sh
```

Type your Mac password when asked (it stays invisible while you type), then **hit your MacBook**. 💥

Press **Ctrl + C** to stop.

> First time? If Terminal says `swift: command not found`, run `xcode-select --install`, click **Install**, wait for it to finish, then run `./run.sh` again.

---

## ⚙️ Options

Add these after `./run.sh`:

| Option | What it does | Example |
|---|---|---|
| `-t <g>` | Sensitivity. **Lower = more sensitive.** Default `0.15` | `./run.sh -t 0.3` |
| `-d` | Debug mode: shows live sensor values so you can tune `-t` | `./run.sh -d` |
| `-s <folder>` | Use your own sounds (`.mp3` `.wav` `.m4a` `.aiff`) | `./run.sh -s ~/Desktop/my-sounds` |
| `-o` | Let hits overlap instead of waiting for the sound to finish | `./run.sh -o` |
| `-c <sec>` | Minimum time between hits. Default `0.35` | `./run.sh -c 1` |

**Too sensitive (goes off when you type)?** → `./run.sh -t 0.3`
**Not sensitive enough?** → `./run.sh -t 0.08`

### Your own sounds
Put one or more audio files in a folder and point MacSlap at it. With several files, it picks one at random on every hit:

```bash
./run.sh -s ~/Desktop/my-sounds
```

Or just replace the file in the `sounds/` folder.

---

## 🧠 How it works

```
 slap → motion sensor → IOKit HID → filter out gravity → is it a hit? → 🔊 play sound
```

1. **The hidden sensor.** Apple Silicon MacBooks (M2 and later) have an accelerometer, a chip that measures movement, managed by Apple's sensor processor (SPU). Apple has no public API for it, but it appears in the system as `AppleSPUHIDDevice`.
2. **Waking it up.** MacSlap turns on reporting for the sensor through IOKit and opens the accelerometer (vendor usage page `0xFF00`, usage `3`). This is why it needs `sudo`.
3. **Reading data.** The sensor sends hundreds of reports per second. Each report contains X, Y and Z acceleration as 32-bit integers, which MacSlap converts to *g* (1 g = Earth's gravity).
4. **Ignoring gravity and tilting.** A slow-moving average tracks gravity and how the laptop is sitting. MacSlap subtracts it, so only **sudden shocks** are left.
5. **Detecting a hit.** If a shock is bigger than the threshold (`-t`), it's a hit. MacSlap takes the strongest value in the next 30 ms to measure how hard you hit.
6. **Playing the sound.** Harder hits play louder. While the sound is playing, new hits are ignored, so you always hear the full scream. This also stops the speaker's own vibration from triggering it again.

All the code is in one file: [`Sources/MacSlap/main.swift`](Sources/MacSlap/main.swift).

---

## 🛠 Troubleshooting

| Problem | Fix |
|---|---|
| `No accelerometer found` | Your Mac doesn't have the sensor (M1, Intel or desktop Mac). |
| `Permission denied` running `./run.sh` | Run `chmod +x run.sh` once, or use `bash run.sh`. |
| `Killed: 9` | Run `codesign --force --sign - .build/release/MacSlap`, then try again. |
| Goes off when typing | Raise the threshold: `./run.sh -t 0.3`. Use `-d` to see the values. |
| Nothing happens when hitting | Run `./run.sh -d`. If no numbers appear at all, open an issue with your Mac model and macOS version. |
| No sound | Check the volume and output device. Try `./run.sh -s /System/Library/Sounds`. |

---

## ⚠️ Disclaimer

- This uses a **private, undocumented** Apple interface. It could stop working after a macOS update, and it can't be published on the App Store.
- It only reads the sensor. Nothing is changed on your system, and it stops when you press Ctrl + C.
- Hit your MacBook **gently**. MacSlap is not responsible for broken screens or hurt hands. 🙃

## 🙏 Credits

- Sensor details come from [olvvier/apple-silicon-accelerometer](https://github.com/olvvier/apple-silicon-accelerometer).
- The "AUUGHHH" sound is a popular internet meme sound effect. It's included for fun, and all rights belong to its original creator.

## 📄 License

[MIT](LICENSE). Use it, change it, share it.
