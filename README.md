# syncR

I was tired of fiddling around with Audio MIDI Setup to get my Poly Sync 20 in sync with my monitor speakers – no matter what I tried (combined audio device, macOS built-in sync feature), it just didn't work. The Poly Sync, like many other USB speakers, has a DSP built in which delays the audio. On top of that, the **Multi-Output Device**:

- **has no joint volume control.** A Multi-Output Device has no master volume – the keyboard keys and the
  menu bar slider do nothing.
- **can not sync the internal delay of the USB speaker.** Many devices process audio internally (echo cancellation, DSP, Bluetooth …) and
  don't report that delay to macOS. A speakerphone can easily be 80 ms behind the other speaker...

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

When syncR is disabled, audio simply plays on the main device.

## Requirements

- macOS 15 or later (Apple silicon or Intel)

## Download

1. Download `syncR-x.y.zip` from [Releases](https://github.com/znrR/syncr/releases), unzip it and move
   `syncR.app` to your Applications folder.
2. The app is not notarized by Apple, so macOS blocks the first start. Open it once, then go to
   **System Settings → Privacy & Security** and click **Open Anyway**. Or in Terminal:

       xattr -dr com.apple.quarantine /Applications/syncR.app

On first start macOS asks for **System Audio Recording** permission (required) and, to measure, for the **Microphone**.

## Build from source

Needs a Swift toolchain (Xcode or Command Line Tools: `xcode-select --install`).

    git clone https://github.com/znrR/syncr.git
    cd syncr
    ./build.sh            # builds ~/Applications/syncR.app (ad-hoc signed)
    open ~/Applications/syncR.app

`./release.sh` builds a universal zip into `build/`.

## Setup

1. Click the speaker icon in the menu bar → gear icon.
2. Choose the **main device** (gets the system volume, e.g. your speakerphone) and the
   **second device**.
3. Choose a **measurement mic**, pause all audio, put the mic where you listen and click
   **Measure delay**.
4. Turn on **syncR on**. Adjust the balance with the per-device volume sliders.

Tip: for calls & video conferencing, turn syncR off. Speakerphones cancel echo only for audio they play themselves.

## Command line tools (optional)

    tools/build.sh        # builds syncrctl and syncr-ltas into ~/.local/bin

- `syncrctl state` – current settings · `syncrctl set '{"secondDB": 3}'` – change settings
- `syncrctl measure 60 music` – record 60 s of system audio + the measurement mic (enable
  *Allow remote measurements* in Setup first)
- `syncr-ltas ~/Library/Logs/syncR/measurements/music.f32` – tonal balance at the listening
  position (1/3 octave, relative to system audio). Works with any music, no test signals needed.

## Limitations

- The app is ad-hoc signed, not notarized (see Download).
- Both devices play the full range; there is no crossover.
- Device delays can differ slightly between low and high frequencies – the measured value is
  tuned for mids/highs (2 kHz clicks).

## License

No license, do whatever you want with it :) hope it fixes your sync problem! (The Unlicense)
