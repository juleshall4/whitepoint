# White Point

White Point is a native macOS menu bar prototype that dims all colours evenly on the main display. It uses no third-party packages, network connections, or screen overlay. Follow Night Shift checks status every 30 seconds as a fallback.

## Use the app

1. Open **White Point.app**.
2. Click the half-filled circle in the menu bar.
3. Select **Reduce white point** and move the **Intensity** slider.
4. Select **Choose shortcut** and press a key combination that includes Control, Option, or Command. Press Escape to cancel or select **Clear** to remove the shortcut.
5. Select **Launch at login** if desired. macOS may require approval in System Settings.
6. Select **Quit and restore display** to quit normally.

The app starts with the effect off on its first launch. Later launches remember the last on/off state. Intensity starts at 35%. Launch at login starts off.

Keep the app at a stable location before enabling launch at login. You can move it to your Applications folder; quit it normally before moving it, reopen it there, then enable launch at login.

## Schedule on and off

Select **Schedule…** in the menu bar panel.

- **Off — manual control:** use the toggle or your shortcut.
- **Custom schedule:** independently choose **Time**, **Sunset**, or **Sunrise** for **On** and **Off**. Fixed times follow the Mac's current time zone. Select **Use sunset → sunrise** for the usual overnight preset.
- **Follow Night Shift:** follow Night Shift's actual on/off state, including its custom schedule, solar schedule, and manual changes. This is the closest timing match to Night Shift.

Sun events require a saved location. Enter latitude and longitude, or select **Use current location…** and approve the macOS location prompt. The app saves that single location on this Mac and calculates locally. Update it after travelling. Follow Night Shift does not require White Point to obtain your location.

Settings save immediately. Invalid or incomplete schedules show a message and pause scheduling without changing the current effect. Near polar regions where sun events are missing, use fixed times.

A manual toggle temporarily overrides automatic control until the next scheduled transition or Night Shift state change. Restarting the app or editing the schedule resumes automatic control immediately. Changing intensity does not suspend the schedule. The app catches up after sleep and clock/time-zone changes.

Scheduling starts off. The app must be running for any schedule to work; use **Launch at login** for daily use. It does not wake a sleeping Mac.

### Apple and solar timing

Apple documents Night Shift as using the clock and geolocation to determine sunset. The documentation reviewed does not specify its exact solar calculation or expose a public Night Shift status API.

Follow Night Shift uses a read-only internal CoreBrightness status interface. It listens for changes and checks status every 30 seconds as a fallback. The app does not modify Night Shift settings. The reader validates the interface layout and reports unavailable if incompatible; Apple could change it in a future macOS release. State following was tested on this Mac, but the latency of a real sunset transition has not been observed.

Independent sun schedules use NOAA's fractional-year equations with the apparent sun horizon at −0.833° (including refraction and the sun's radius). This is sunrise/sunset, rather than the end of civil or astronomical twilight. These are estimates and may differ by several minutes from Apple. A Greenwich reference fixture agrees with US Naval Observatory sun times within five minutes. Choose **Follow Night Shift** when matching Apple's timing matters most.

## How the effect works

The app saves the main display's colour lookup table and multiplies every red, green, and blue output value by the same factor. Dark tones, midtones, and highlights all receive the same proportional reduction. Black remains black.

This produces uniform, blanket-like dimming instead of selectively compressing highlights. The factor is `1 - 0.9 × intensity`, where intensity ranges from 0 to 1. At the default 35% intensity, the app retains 68.5% of each saved output value. Maximum intensity retains 10%, so the app never intentionally makes the display completely black.

The slider measures this app's strength, not physical luminance or Apple's percentage scale. Apple does not specify its exact colour transformation in the documentation reviewed. This is an approximation inspired by the observed behaviour of Reduce White Point, not a verified implementation of Apple's algorithm.

## Limitations

- HDR content, Night Shift, True Tone, display reconnection, and login launch need hands-on testing.
- Other apps or system features that change colour tables can override this effect. Turn White Point off before changing those settings, then turn it on again.
- Force quitting or a crash bypasses normal restoration. Reopening may capture an already adjusted table. If colours remain altered, quit the app and log out and back in to reset the display session.
- The app is locally signed for this Mac, not notarized for general distribution.
- The build targets Apple Silicon and requires macOS 13 or later.

## Build from source

Run `./build.sh` from this folder with the Swift command-line tools installed. The script compiles the Swift source and locally signs the app bundle.

## Validation

Version 0.3.0 retains a regression check for equal scaling across tones and RGB channels, monotonic output, black preservation, and identity at zero. The old highlight curve fails that check.

Live checks at 35%, 70%, and zero intensity returned the expected main-display tables with no measured difference. Restoration matched the original RGB tables exactly. The external display's table remained unchanged throughout.

Run the checks from this folder:

```sh
'White Point.app/Contents/MacOS/WhitePoint' --check-curve
# Quit the app normally before the live display check.
'White Point.app/Contents/MacOS/WhitePoint' --check-display
```

Table checks establish the applied signal and restoration; they do not establish an exact perceptual match to iOS or HDR behaviour. Schedule validation passed 33 checks covering overnight/daytime boundaries, daylight-saving gaps and repeated hours, missing location, mixed sources, polar dates, time-zone date boundaries, persistence, and independent sun-time fixtures. A live scheduler check verified on/off display application, manual override behaviour, timer creation, and available Night Shift state following. Desktop UI inspection remains unverified because the automation tool previously timed out.

Run `./test-schedule.sh` for the deterministic schedule checks. After quitting the app normally, run `'White Point.app/Contents/MacOS/WhitePoint' --check-scheduler` for the live controller check. This briefly adjusts then restores the main display.

## References

- [Apple: Reduce White Point](https://support.apple.com/en-au/111773)
- [Apple: Display gamma controls](https://developer.apple.com/documentation/coregraphics/quartz-display-services)
- [Apple: Launch at login](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp)

- [Apple: Night Shift scheduling](https://support.apple.com/en-la/102191)
- [NOAA: Solar event equations](https://gml.noaa.gov/grad/solcalc/solareqns.PDF)
- [US Naval Observatory: Solar reference API](https://aa.usno.navy.mil/data/api)
