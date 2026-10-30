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
./build.sh install    # builds and moves it to /Applications
swift test            # runs the unit tests
```

With only the Command Line Tools installed, `swift test` intermittently fails with "plugin for
module 'TestingMacros' not found", mostly after a debug `swift build`. Running it again clears
it, occasionally only on the second or third try.

If retries do not help with Command Line Tools, explicitly provide its Testing plugin path:

```sh
swift test -Xswiftc -plugin-path -Xswiftc "$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
```

Balarm plays the Radial tone from the system's ToneLibrary, so neither the repository nor the
app contains Apple audio. The app is ad-hoc signed.

Keep a single copy of `Balarm.app`: with a second one, clicking the alarm's notification can
start that copy as a second Balarm. `./build.sh install` therefore moves the app rather than
copying it, and a plain `./build.sh` warns when Balarm is installed as well.

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

While an alarm runs, it also shows in the menu bar with the time left, like a timer's Live
Activity, and the time left shows on Balarm's Dock icon. The menu bar item's menu pauses,
restarts or cancels the alarm, stops or repeats it while it rings, and shows the window again.
Closing the window leaves a running or paused alarm in the menu bar, and clicking Balarm in the
Dock brings the window back; closing it while the alarm rings stops it, like **Stop**. Without
an alarm, closing the window quits Balarm, and once an alarm ends with the window closed,
Balarm quits too. Quitting cancels a running alarm.

While an alarm runs, the Mac does not go to sleep on its own; if it sleeps anyway (lid
closed), the alarm rings right after waking.

## Notifications

On first launch macOS asks whether Balarm may send notifications. For the alarm's alert to
stay on screen until the alarm is stopped, set Balarm's alert style to **Persistent** in System
Settings › Notifications › Balarm: macOS gives Balarm temporary alerts at first and lets only
you change that. While the alerts are temporary or turned off, Balarm shows a note with a
button that opens Notification settings. The time left on Balarm's Dock icon shows only while
badges are allowed there as well.

Closing the alert with its ✕, or clearing it in Notification Center, stops the alarm like
**Stop**. With persistent alerts, swiping it away does too, about half a second after a
trackpad swipe or a few seconds after dragging it away with the mouse: macOS does not report a
swipe, so Balarm notices the alert leaving the screen right after one. Balarm cannot see whose
notifications are on screen, so a swipe goes unnoticed while another notification is showing as
well, for the whole alert if one was already on screen when the alarm rang, once a Focus has
hidden the alert, and with temporary alerts, which leave by themselves. It also goes unnoticed
right after unlocking the screen, ending the screen saver or waking the display, which may
briefly take notifications off the screen, and may go unnoticed for an alarm that rang while
the display was asleep. In rare cases, a Focus switching on just as you scroll or drag
something can stop the alarm. Clicking the alert brings Balarm forward and shows the alert
again a second later, since the alarm rings on until it is stopped.

The tone is played by the app itself, so it rings even when notifications are off or a Focus
mode is active. A Focus mode can still hold back the alert itself: letting it through needs
the Time Sensitive entitlement, which an ad-hoc signed app cannot carry.

## License

MIT — see [LICENSE](LICENSE).

## AI Honesty

This project was completely generated by LLMs.

<a href="https://www.aihonestybadge.com" target="_blank" rel="noopener"><img src="https://www.aihonestybadge.com/badges/ai-generated.svg" alt="AI Generated Badge" style="max-width: 190px; height: auto;" /></a>
