# White Point

A lightweight macOS menu bar app inspired by iOS Reduce White Point. It dims all colours evenly on the main display, with an intensity slider, a user-selected shortcut, optional launch at login, and scheduling.

Requires Apple Silicon and macOS 13 or later. No third-party packages are required.

## Build and run

Install Apple's Swift command-line tools, then run:

```sh
./build.sh
open 'White Point.app'
```

The script creates a locally signed app bundle. This build is not notarized for public distribution.

## Use the app

Click the half-filled circle in the menu bar. Enable **Reduce white point** and adjust **Intensity**. Select **Choose shortcut** to record a combination containing Control, Option, or Command; press Escape to cancel or **Clear** to remove it.

The app remembers intensity, shortcut, and on/off state. Optional **Launch at login** starts disabled. Keep the app at a stable location before enabling it.

## Schedule on and off

Select **Schedule…** and choose a mode:

- **Off — manual control:** use the toggle or shortcut.
- **Custom schedule:** independently select a fixed time, sunset, or sunrise for on and off. Sun events need saved coordinates or a one-shot **Use current location…** request. Location stays on this Mac; update it after travel.
- **Follow Night Shift:** follow Night Shift's actual on/off state without changing its settings or requesting your location.

Manual toggles override automatic control until the next scheduled transition or Night Shift state change. Restarting or editing the schedule resumes automatic control. Scheduling catches up after sleep and clock/time-zone changes. The app must remain running; it does not wake a sleeping Mac. Invalid schedules pause automatic changes and show a message.

## Display behaviour and limitations

The app scales every saved RGB output value by the same factor, preserving black. The slider is this app's intensity scale, not Apple's scale or a measurement of physical light output. Normal disable or quit restores the saved display curve.

- Follow Night Shift uses an internal macOS interface, with notifications and a 30-second fallback check. Future macOS versions may change it; the app reports unavailable status when incompatible.
- Independent sun times use NOAA's apparent sunrise/sunset convention and can differ from Apple's times by several minutes. Use fixed times where polar sun events are missing.
- HDR, True Tone, Night Shift colour interactions, and other display utilities require hands-on testing. Turn the effect off before changing other colour adjustments, then turn it on again.
- Force quitting or a crash bypasses restoration. If colours remain altered, quit the app and log out and back in to reset the display session.

## Run checks

```sh
./test-schedule.sh
'White Point.app/Contents/MacOS/WhitePoint' --check-curve
```

After quitting the app normally, run the live checks, which briefly adjust and restore the main display:

```sh
'White Point.app/Contents/MacOS/WhitePoint' --check-display
'White Point.app/Contents/MacOS/WhitePoint' --check-scheduler
```

Schedule tests cover overnight boundaries, daylight-saving changes, mixed event types, missing sun events, persistence, and independent solar reference times. Live checks verify display application, restoration, and scheduler overrides. They do not establish an exact visual match to iOS.

## References

- [Apple: Night Shift scheduling](https://support.apple.com/en-la/102191)
- [NOAA: Solar event equations](https://gml.noaa.gov/grad/solcalc/solareqns.PDF)
- [US Naval Observatory: Solar reference API](https://aa.usno.navy.mil/data/api)
