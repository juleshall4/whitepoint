# Add scheduled white point reduction

## Goal

Schedule the approved uniform white point effect on and off, using either fixed times or sunrise/sunset. Provide the closest available timing match to Night Shift without changing Night Shift settings.

## Delivered behaviour

- A separate Schedule window, accessible from the menu bar panel.
- Off/manual, custom schedule, and Follow Night Shift modes.
- Independent Time/Sunset/Sunrise sources for on and off; sunset-to-sunrise preset.
- Saved coordinates or a user-requested, one-shot Core Location lookup. Coordinates remain local and can be updated after travel.
- Automatic catch-up on startup, wake, clock changes, and time-zone changes.
- A manual toggle overrides until the next scheduled transition or Night Shift state change. Restart or schedule edits resume automatic control.
- Scheduling initially disabled; existing intensity, enabled state, shortcut, and login preference retained.
- Uniform colour reduction unchanged from the user-approved version.

## Research and implementation

Apple documents the use of clock and geolocation for Night Shift's solar schedule, but the documentation reviewed does not disclose the exact solar calculation. Independent schedules use NOAA's apparent sunrise/sunset convention (zenith 90.833°, allowing for refraction and solar radius), rather than twilight.

Follow Night Shift reads the actual active state through the local CoreBrightness private framework. The reader dynamically checks availability and validates the status method ABI before use. It subscribes to status notifications and checks every 30 seconds as a fallback. It does not set Night Shift state, schedule, or colour temperature. If unavailable, the UI reports this and offers time scheduling rather than silently substituting estimated solar timing.

Custom schedules evaluate timestamped events across civil dates, including overnight intervals and DST boundaries. They arm a one-shot timer for the next transition or midnight. Invalid schedules pause automatic updates and display a reason. Missing polar sun events require fixed-time scheduling.

## Validation

- Build and local signature verification.
- 33 deterministic schedule checks: overnight/daytime exact boundaries, next transition, invalid same times, DST missing/repeated times, solar location requirement, solar boundaries, mixed fixed/solar endpoints, polar dates, coordinate validation, civil/UTC date boundaries, persistence, and independent USNO reference times.
- Greenwich test date 2026-09-30: estimated sunrise 06:56 BST and sunset 18:42 BST, compared with USNO 06:59 and 18:40; within the five-minute tolerance.
- Live scheduler check: on/off reaches display controller, timer is armed, manual overrides hold and expire, disabled scheduling retains manual state, and Follow Night Shift matches available local status.
- Existing uniform-dimming and display-table restoration checks pass; other display remains unchanged.

## Limits

Real sunset-transition notification latency, the location permission flow, login launch, and visual layout need hands-on assessment. Private Night Shift interfaces can change across macOS versions. Sun-event estimates are not guaranteed to equal Apple's times. The app must remain running and does not wake the Mac. Saved sun location is updated on request, not continuously tracked. Normal quit restores the saved display curve; forced termination bypasses cleanup.

## Sources

- [Apple: Night Shift on Mac](https://support.apple.com/en-la/102191)
- [NOAA: Solar equations](https://gml.noaa.gov/grad/solcalc/solareqns.PDF)
- [USNO: API documentation and sun reference data](https://aa.usno.navy.mil/data/api)
- Local CoreBrightness method inspection on this Mac; internal interface, not a published Apple API.
