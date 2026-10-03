# syncR

**Play your Mac's audio on two speakers at once – in sync, with one volume control.**

I have a Poly Sync 20 speaker on my desk and a monitor with built-in speakers, and I wanted
music to play on both. Achieving this via the macOS Audio MIDI Setup and a Multi-Output Device failed:

- **Sync fails.** The Poly Sync runs everything through a DSP (for echo cancellation and other stuff)
  before it plays a sound – about 80 ms of delay that it never tells macOS about. So macOS happily
  lines up the two devices, and one of them is still way behind. I assume many other USB and Bluetooth speakers
  do this.
- **No joint volume control.** A Multi-Output Device has no master volume. The keyboard keys
  and the menu bar slider just stopped working.

I couldn't find anything that fixes this, so I built syncR with the help of Claude Code.

## What it does

- **Real sync, based on measuring.** Hit *Measure delay*: syncR plays a few clicks on each device, listens
  with any microphone (my iPhone worked great) and sets the delay for you. Fine-tuning by
  human ear can be done in the app in 0.1 ms steps.

- **One master volume.** Your *main device* stays the normal system output, so the volume keys,
  the menu bar slider and the speaker's own buttons work like always. The second device simply
  follows along and keeps the balance which is set in the app.

- **The little extras.** Volume per device, a simple bass/mid/treble EQ per device, mute and a panel
  you can tear off the menu bar. Turn syncR off (e.g. for a conference call) and everything plays on
  the main device again.

## Download

**Download:** `syncR-x.y.zip` from [Releases](https://github.com/znrR/syncr/releases), unzip it
and drag `syncR.app` into Applications. Should work on Apple silicon and Intel Macs with macOS 15 or later.

The app isn't notarized by Apple, so macOS will refuse to open it the first time. Try once, then go
to **System Settings → Privacy & Security** and click **Open Anyway**. Or, in Terminal:

    xattr -dr com.apple.quarantine /Applications/syncR.app

**Or build it yourself** (needs Xcode or the Command Line Tools – `xcode-select --install`):

    git clone https://github.com/znrR/syncr.git
    cd syncr
    ./build.sh
    open ~/Applications/syncR.app

On first launch, macOS asks whether syncR may record system audio – it needs that to work. To
measure the delay, it also asks for microphone access.

## Set it up

1. Click the speaker icon in the menu bar, then the gear.
2. Pick your **main device** (the one whose volume buttons you want to use – e.g. your
   speakerphone) and your **second device**.
3. Pick a **measurement mic**, pause your music, put the mic where you usually sit and click
   **Measure delay**.
4. Switch **syncR on** and adjust the balance with the two volume sliders.

**Recommended:** Turn syncR off for Zoom, Teams & co. A speakerphone can only cancel the echo
of sound it plays itself – sound from the second speaker would most likely leak back into your call.

## How it works

syncR grabs all system audio with a Core Audio *process tap* and mutes the original output. It
then plays the audio through a private aggregate device made of your two speakers – clocked by the
main device, with drift correction for the second – and applies the gain, EQ and delay along the
way. While syncR is on, the second device's own hardware volume stays at 100 % and syncR does the
level control. Its built-in microphone (if it has one) is switched off, so the orange mic indicator
stays dark.

## Good to know

- Both speakers play the full frequency range; there's no crossover. I tried one, but it just made
  the sound worse. The simple EQ is worth a try though.
- Some devices delay low and high frequencies slightly differently. The measured value is tuned for
  mids and highs, which is where sync matters most.

## License

No license, do whatever you want with it :) Hope it fixes your sync problem too! (The Unlicense)

Created with the help of [Claude Code](https://claude.com/claude-code).
