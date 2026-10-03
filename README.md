# syncR

Play your Mac's audio on **two output devices at once – in sync, with one volume control.**

A small macOS menu bar app for setups like *USB speakerphone + monitor speakers*, where macOS's own
**Multi-Output Device** falls short:

- **No volume control.** A Multi-Output Device has no master volume – the keyboard keys and the
  menu bar slider do nothing.
- **Out of sync.** Many devices process audio internally (echo cancellation, DSP, Bluetooth …) and
  don't report that delay to macOS. A speakerphone can easily be 80 ms behind the other speaker,
  which sounds like an echo.

syncR fixes both:

- **One volume for both devices.** The *main device* becomes the system output, so the keyboard,
  the menu bar slider and the device's own buttons work as usual – the second device follows,
  keeping the balance you set.
- **Measured sync.** *Measure delay* plays short clicks on both devices, records them with any
  microphone (an iPhone via Continuity works well) and sets the delay automatically. Fine-tune by
  ear in 0.1 ms steps.
- Per-device volume, a simple 3-band EQ per device, mute, detachable panel, launch at login.

## How it works

syncR captures all system audio with a Core Audio **process tap** (macOS 14.2+), muting the
original output. It plays the audio through a private aggregate device made of your two outputs
(clocked by the main device, drift-corrected for the second one), applies gain, EQ and delay, and
keeps the second device's hardware volume at 100 % while it's on. The second device's own
microphone is switched off in the aggregate, so no microphone indicator stays lit.

When syncR is off, audio simply plays on the main device.

## Requirements

- macOS 15 or later
- Swift toolchain (Xcode or Command Line Tools: `xcode-select --install`)

## Build & install

```bash
git clone https://github.com/znrR/syncr.git
cd syncr
./build.sh            # builds ~/Applications/syncR.app (ad-hoc signed)
open ~/Applications/syncR.app
```

On first start macOS asks for **System Audio Recording** permission (required) and, when you
measure, for the **Microphone**.

## Setup

1. Click the speaker icon in the menu bar → gear icon.
2. Choose the **main device** (gets the system volume, e.g. your speakerphone) and the
   **second device**.
3. Choose a **measurement mic**, pause all audio, put the mic where you listen and click
   **Measure delay**.
4. Turn on **syncR on**. Adjust the balance with the per-device volume sliders.

Tip: for calls, turn syncR off. Speakerphones cancel echo only for audio they play themselves.

## Command line tools (optional)

```bash
tools/build.sh        # builds syncrctl and syncr-ltas into ~/.local/bin
```

- `syncrctl state` – current settings · `syncrctl set '{"secondDB": 3}'` – change settings
- `syncrctl measure 60 music` – record 60 s of system audio + the measurement mic (enable
  *Allow remote measurements* in Setup first)
- `syncr-ltas ~/Library/Logs/syncR/measurements/music.f32` – tonal balance at the listening
  position (1/3 octave, relative to system audio). Works with any music, no test signals needed.

## Limitations

- The app is ad-hoc signed. If macOS blocks it, build it yourself as shown above.
- Both devices play the full range; there is no crossover.
- Device delays can differ slightly between low and high frequencies – the measured value is
  tuned for mids/highs (2 kHz clicks).

## License

MIT
