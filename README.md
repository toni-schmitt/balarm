# Balarm

A single, keyboard-first countdown alarm for macOS. Type the duration, press Return, done —
no date-picker fields that reset when you type too slowly.

It rings like Clock.app: the same default tone (Radial), looping until you stop it, and an
alert with **Stop** and **Repeat**.

## Requirements

- macOS 26 or later
- Swift 6.2+ (Xcode Command Line Tools are enough; Xcode is not needed)

## Build and install

```sh
./build.sh            # builds build/Balarm.app
./build.sh install    # builds and copies it to /Applications
swift test            # runs the unit tests
```

With only the Command Line Tools installed, `swift test` intermittently fails with "plugin for
module 'TestingMacros' not found", mostly after a debug `swift build`. Running it again clears
it, occasionally only on the second or third try.

If retries do not help with Command Line Tools, explicitly provide its Testing plugin path:

```sh
swift test -Xswiftc -plugin-path -Xswiftc "$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
```

`build.sh` copies the Radial tone from the system's ToneLibrary into the app bundle, so the
repository contains no Apple audio. The app is ad-hoc signed.

## Usage

Digits fill `hh:mm:ss` from the right, like a microwave. A field may overflow and carries
over, so `90` runs for 1 min 30 s.

Click the duration display to edit labeled Hours, Minutes, and Seconds fields, which also
work with VoiceOver and Voice Control. Save applies the duration; Return or Start then starts it.
While running or paused, the Restart button starts over after confirmation, just like `R`.

| You type | Display    | Runs for      |
| -------- | ---------- | ------------- |
| `5`      | `00:00:05` | 5 s           |
| `500`    | `00:05:00` | 5 min         |
| `2500`   | `00:25:00` | 25 min        |
| `13000`  | `01:30:00` | 1 h 30 min    |

| Key            | Typing                     | Running        | Ringing |
| -------------- | -------------------------- | -------------- | ------- |
| `0`–`9`        | add a digit                |                |         |
| Delete         | remove the last digit      |                |         |
| Return         | start                      |                | stop    |
| Space          |                            | pause / resume |         |
| Esc or `⌘.`    | clear                      | cancel         | stop    |
| `R`            |                            | restart (asks) | repeat  |

After an alarm ends, its duration stays in the input (dimmed): Return starts it again,
typing a digit replaces it, and Delete clears it at once. The last duration is remembered
across launches.

Closing the window quits Balarm and cancels a running alarm. While an alarm runs, the Mac
does not go to sleep on its own; if it sleeps anyway (lid closed), the alarm rings right after
waking.

## Notifications

On first launch macOS asks whether Balarm may send notifications. Balarm asks for the
persistent **Alerts** style, which you can change in System Settings › Notifications › Balarm.

The tone is played by the app itself, so it rings even when notifications are off or a Focus
mode is active. A Focus mode can still hold back the alert itself: letting it through needs
the Time Sensitive entitlement, which an ad-hoc signed app cannot carry.
