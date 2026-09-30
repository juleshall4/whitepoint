import AppKit
import CoreGraphics
import Carbon
import ServiceManagement
import CoreLocation

func soften(_ value: Float, amount: Float) -> Float {
    let strength = min(max(amount, 0), 1)
    return value * (1 - 0.9 * strength)
}

struct GammaTable {
    let display: CGDirectDisplayID
    let red: [Float]
    let green: [Float]
    let blue: [Float]

    init(display: CGDirectDisplayID) throws {
        let capacity = CGDisplayGammaTableCapacity(display)
        guard capacity > 0 else { throw AppError.message("This display does not support colour adjustment.") }
        var r = [Float](repeating: 0, count: Int(capacity))
        var g = r, b = r
        var count: UInt32 = 0
        let result = CGGetDisplayTransferByTable(display, capacity, &r, &g, &b, &count)
        guard result == .success, count > 1 else { throw AppError.message("Could not read the display’s colour settings (\(result.rawValue)).") }
        self.display = display
        red = Array(r.prefix(Int(count))); green = Array(g.prefix(Int(count))); blue = Array(b.prefix(Int(count)))
    }

    func write(amount: Float = 0) throws {
        let r = red.map { soften($0, amount: amount) }
        let g = green.map { soften($0, amount: amount) }
        let b = blue.map { soften($0, amount: amount) }
        let result = CGSetDisplayTransferByTable(display, UInt32(r.count), r, g, b)
        guard result == .success else { throw AppError.message("Could not adjust the display (\(result.rawValue)).") }
    }
}

enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, CLLocationManagerDelegate {
    let defaults: UserDefaults
    let popover = NSPopover()
    var status: NSStatusItem!
    var toggle: NSButton!
    var slider: NSSlider!
    var amountLabel: NSTextField!
    var shortcutButton: NSButton!
    var loginButton: NSButton!
    var message: NSTextField!
    var schedule: ScheduleSettings
    var scheduleTimer: Timer?
    var overrideUntil: Date?
    var overrideNightShift = false
    var lastNightShiftState: Bool?
    var scheduleLabel: NSTextField!
    var scheduleWindow: NSWindow?
    var scheduleWindowLabel: NSTextField?
    var modePicker: NSPopUpButton!
    var onEventPicker: NSPopUpButton!
    var offEventPicker: NSPopUpButton!
    var onTimePicker: NSDatePicker!
    var offTimePicker: NSDatePicker!
    var latitudeField: NSTextField!
    var longitudeField: NSTextField!
    var locationLabel: NSTextField!
    lazy var locationManager = CLLocationManager()
    var requestingLocation = false
    var baseline: GammaTable?
    var enabled = false
    var sleeping = false
    var hotKey: EventHotKeyRef?
    var hotKeyHandler: EventHandlerRef?
    var recordingMonitor: Any?
    var reconfiguration: DispatchWorkItem?
    var observers: [NSObjectProtocol] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.schedule = ScheduleSettings.load(defaults)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        defaults.register(defaults: ["amount": 35.0, "enabled": false])
        enabled = defaults.bool(forKey: "enabled")
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: "White Point")
        status.button?.target = self; status.button?.action = #selector(showPopover)
        buildUI()
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let app = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            app.toggleEffect()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler)
        registerSavedShortcut()
        CGDisplayRegisterReconfigurationCallback({ _, flags, context in
            guard !flags.contains(.beginConfigurationFlag), let context else { return }
            let app = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { app.scheduleDisplayRefresh() }
        }, Unmanaged.passUnretained(self).toOpaque())
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }; self.sleeping = true; self.restore()
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sleeping = false; self?.updateSchedule(); self?.scheduleDisplayRefresh()
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.updateLoginState() })
        apply()
        startScheduling()
        showPopover()
    }

    func buildUI() {
        let controller = NSViewController()
        controller.view = NSView(frame: NSRect(x: 0, y: 0, width: 350, height: 410))
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        controller.view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor, constant: 20), stack.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor, constant: -20), stack.topAnchor.constraint(equalTo: controller.view.topAnchor, constant: 20)])
        let title = NSTextField(labelWithString: "White Point")
        title.font = .systemFont(ofSize: 20, weight: .semibold); stack.addArrangedSubview(title)
        let subtitle = NSTextField(wrappingLabelWithString: "Dim all colours evenly on your main display.")
        stack.addArrangedSubview(subtitle)
        toggle = NSButton(checkboxWithTitle: "Reduce white point", target: self, action: #selector(toggleEffect))
        stack.addArrangedSubview(toggle)
        amountLabel = NSTextField(labelWithString: "")
        stack.addArrangedSubview(amountLabel)
        slider = NSSlider(value: defaults.double(forKey: "amount"), minValue: 0, maxValue: 100, target: self, action: #selector(changeAmount))
        slider.isContinuous = true; slider.setAccessibilityLabel("White point reduction intensity")
        stack.addArrangedSubview(slider)
        slider.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        let shortcutRow = NSStackView()
        shortcutRow.spacing = 8
        shortcutButton = NSButton(title: "Choose shortcut…", target: self, action: #selector(recordShortcut))
        shortcutRow.addArrangedSubview(shortcutButton)
        shortcutRow.addArrangedSubview(NSButton(title: "Clear", target: self, action: #selector(clearShortcut)))
        stack.addArrangedSubview(shortcutRow)
        loginButton = NSButton(checkboxWithTitle: "Launch at login", target: self, action: #selector(toggleLogin))
        stack.addArrangedSubview(loginButton)
        let scheduleRow = NSStackView(); scheduleRow.spacing = 8
        scheduleRow.addArrangedSubview(NSButton(title: "Schedule…", target: self, action: #selector(showSchedule)))
        stack.addArrangedSubview(scheduleRow)
        scheduleLabel = NSTextField(wrappingLabelWithString: "Schedule off.")
        scheduleLabel.font = .systemFont(ofSize: 11); scheduleLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(scheduleLabel)
        message = NSTextField(wrappingLabelWithString: "")
        message.font = .systemFont(ofSize: 11); message.textColor = .secondaryLabelColor
        stack.addArrangedSubview(message)
        stack.addArrangedSubview(NSButton(title: "Quit and restore display", target: self, action: #selector(quit)))
        popover.contentViewController = controller; popover.behavior = .transient; popover.delegate = self
        popover.contentSize = controller.view.frame.size
        refreshUI(); updateLoginState()
    }

    @objc func showPopover() {
        guard let button = status.button else { return }
        if popover.isShown { stopRecording(); popover.performClose(nil) }
        else { updateLoginState(); popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY); NSApp.activate(ignoringOtherApps: true) }
    }

    func popoverDidClose(_ notification: Notification) { stopRecording() }

    func refreshUI() {
        toggle.state = enabled ? .on : .off
        amountLabel.stringValue = "Intensity: \(Int(defaults.double(forKey: "amount")))%"
        status.button?.toolTip = enabled ? "White Point: on" : "White Point: off"
    }

    @objc func toggleEffect() {
        noteManualOverride()
        enabled.toggle(); defaults.set(enabled, forKey: "enabled"); apply(); updateSchedule()
    }
    @objc func changeAmount() {
        defaults.set(slider.doubleValue, forKey: "amount"); apply()
    }
    func apply() {
        refreshUI()
        guard enabled, !sleeping else { restore(); return }
        do {
            let main = CGMainDisplayID()
            if let current = baseline, current.display != main {
                if CGDisplayIsOnline(current.display) != 0 { try current.write() }
                baseline = nil
            }
            if baseline == nil { baseline = try GammaTable(display: main) }
            try baseline?.write(amount: Float(defaults.double(forKey: "amount") / 100))
            message.stringValue = "Uniform dimming inspired by iOS Reduce White Point. All colours use the same reduction."
        } catch { message.stringValue = error.localizedDescription }
    }
    func restore() {
        guard let current = baseline else { return }
        if CGDisplayIsOnline(current.display) == 0 { baseline = nil; return }
        do { try current.write(); baseline = nil; message?.stringValue = "Original display colours restored." }
        catch { message?.stringValue = error.localizedDescription }
    }
    func scheduleDisplayRefresh() {
        reconfiguration?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.restore(); self?.apply() }
        reconfiguration = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    @objc func recordShortcut() {
        stopRecording()
        shortcutButton.title = "Press shortcut (Esc cancels)…"
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { self.stopRecording(); return nil }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.contains(.control) || flags.contains(.option) || flags.contains(.command) else {
                self.message.stringValue = "Include Control, Option, or Command in your shortcut."; return nil
            }
            var modifiers: UInt32 = 0
            var label = ""
            if flags.contains(.control) { modifiers |= UInt32(controlKey); label += "⌃" }
            if flags.contains(.option) { modifiers |= UInt32(optionKey); label += "⌥" }
            if flags.contains(.shift) { modifiers |= UInt32(shiftKey); label += "⇧" }
            if flags.contains(.command) { modifiers |= UInt32(cmdKey); label += "⌘" }
            label += (event.charactersIgnoringModifiers ?? "Key \(event.keyCode)").uppercased()
            if self.hotKey != nil, self.defaults.integer(forKey: "shortcutKey") == Int(event.keyCode), self.defaults.integer(forKey: "shortcutModifiers") == Int(modifiers) {
                self.stopRecording(); return nil
            }
            var candidate: EventHotKeyRef?
            let result = RegisterEventHotKey(UInt32(event.keyCode), modifiers, EventHotKeyID(signature: 0x57504F49, id: 1), GetApplicationEventTarget(), 0, &candidate)
            guard result == noErr else { self.message.stringValue = "That shortcut is unavailable. Choose another."; return nil }
            if let previous = self.hotKey { UnregisterEventHotKey(previous) }
            self.hotKey = candidate
            self.defaults.set(Int(event.keyCode), forKey: "shortcutKey")
            self.defaults.set(Int(modifiers), forKey: "shortcutModifiers")
            self.defaults.set(label, forKey: "shortcutLabel")
            self.stopRecording(); self.message.stringValue = "Shortcut saved: \(label)"
            return nil
        }
    }
    func stopRecording() {
        if let recordingMonitor { NSEvent.removeMonitor(recordingMonitor); self.recordingMonitor = nil }
        shortcutButton.title = defaults.string(forKey: "shortcutLabel") ?? "Choose shortcut…"
    }
    func registerSavedShortcut() {
        stopRecording()
        guard defaults.object(forKey: "shortcutKey") != nil else { return }
        let result = RegisterEventHotKey(UInt32(defaults.integer(forKey: "shortcutKey")), UInt32(defaults.integer(forKey: "shortcutModifiers")), EventHotKeyID(signature: 0x57504F49, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        if result != noErr { message.stringValue = "Saved shortcut is unavailable. Choose another." }
    }
    @objc func clearShortcut() {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        for key in ["shortcutKey", "shortcutModifiers", "shortcutLabel"] { defaults.removeObject(forKey: key) }
        stopRecording()
    }
    func updateLoginState() {
        let state = SMAppService.mainApp.status
        loginButton.state = (state == .enabled || state == .requiresApproval) ? .on : .off
        if state == .requiresApproval { message.stringValue = "Approve White Point in System Settings → General → Login Items & Extensions." }
    }
    @objc func toggleLogin() {
        do {
            if loginButton.state == .on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            updateLoginState()
        } catch { message.stringValue = "Launch at login: \(error.localizedDescription)"; updateLoginState() }
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        restore()
        if baseline != nil {
            let alert = NSAlert(); alert.messageText = "Could not restore the display"
            alert.informativeText = "\(message.stringValue) Try turning the effect off again before quitting."
            alert.addButton(withTitle: "Keep app open"); alert.addButton(withTitle: "Quit anyway")
            return alert.runModal() == .alertFirstButtonReturn ? .terminateCancel : .terminateNow
        }
        return .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) {
        scheduleTimer?.invalidate()
        reconfiguration?.cancel(); stopRecording()
        if let hotKey { UnregisterEventHotKey(hotKey) }
    }
}

if CommandLine.arguments.contains("--check-scheduler") {
    guard NSRunningApplication.runningApplications(withBundleIdentifier: "local.julian.WhitePoint").isEmpty else {
        print("Quit White Point normally before running scheduler checks."); exit(1)
    }
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    let suiteName = "local.julian.WhitePoint.SchedulerTests"
    let preferences = UserDefaults(suiteName: suiteName)!
    preferences.removePersistentDomain(forName: suiteName)
    preferences.register(defaults: ["amount": 35.0, "enabled": false])
    let delegate = AppDelegate(defaults: preferences)
    delegate.status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    delegate.buildUI()
    let now = Date()
    let calendar = Calendar.current
    let minute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
    delegate.schedule.mode = "scheduled"
    delegate.schedule.on = ScheduleEndpoint(event: .time, minute: (minute + 1439) % 1440)
    delegate.schedule.off = ScheduleEndpoint(event: .time, minute: (minute + 1) % 1440)
    delegate.updateSchedule()
    precondition(delegate.enabled && delegate.baseline != nil, "Scheduled on must reach the display controller.")
    precondition(delegate.scheduleTimer != nil)
    delegate.toggleEffect()
    precondition(!delegate.enabled && delegate.baseline == nil && delegate.overrideUntil != nil, "Manual override restores the display.")
    delegate.updateSchedule()
    precondition(!delegate.enabled, "A schedule refresh must respect a manual override.")
    delegate.overrideUntil = now.addingTimeInterval(-1)
    delegate.updateSchedule()
    precondition(delegate.enabled, "Expired override must resume the schedule.")
    delegate.schedule.mode = "manual"
    delegate.updateSchedule()
    precondition(delegate.scheduleTimer == nil && delegate.enabled, "Disabling scheduling must retain manual state.")
    delegate.schedule.mode = "nightshift"
    delegate.updateSchedule()
    let nightShift = WPNightShiftActive()
    if nightShift >= 0 {
        precondition(delegate.enabled == (nightShift == 1), "Follow Night Shift must match the actual status.")
        delegate.toggleEffect()
        let overridden = delegate.enabled
        delegate.updateSchedule()
        precondition(delegate.enabled == overridden && delegate.overrideNightShift, "Manual override must survive repeated Night Shift status reads.")
    }
    delegate.scheduleTimer?.invalidate()
    delegate.enabled = false; delegate.apply()
    precondition(delegate.baseline == nil, "Scheduler check must restore the display.")
    preferences.removePersistentDomain(forName: suiteName)
    print("PASS: scheduler applies on/off, arms a timer, respects manual overrides, resumes after expiry, and follows available Night Shift status.")
} else if CommandLine.arguments.contains("--check-nightshift") {
    let state = WPNightShiftActive()
    print(state < 0 ? "Night Shift reader unavailable." : "Night Shift reader available; currently \(state == 1 ? "on" : "off").")
    exit(state < 0 ? 1 : 0)
} else if CommandLine.arguments.contains("--check-curve") {
    for amount: Float in [0, 0.35, 0.7, 1] {
        let whiteScale = soften(1, amount: amount)
        var previous: Float = -1
        for index in 0...1024 {
            let input = Float(index) / 1024
            let output = soften(input, amount: amount)
            guard output >= previous, output <= input + 0.000001,
                  abs(output - input * whiteScale) < 0.000001 else {
                print("FAIL: uneven dimming at intensity \(amount), input \(input): output \(output), expected \(input * whiteScale).")
                exit(1)
            }
            if amount == 0 { precondition(output == input) }
            previous = output
        }
        for colour: [Float] in [[1, 0.2, 0.05], [0.1, 0.8, 0.4], [0.2, 0.2, 0.2]] {
            let reduced = colour.map { soften($0, amount: amount) }
            for channel in 0..<3 { precondition(abs(reduced[channel] / colour[channel] - whiteScale) < 0.000001) }
        }
        precondition(whiteScale > 0)
    }
    print("PASS: uniform scaling across all tones and RGB channels, monotonicity, black preservation, identity at zero.")
} else if CommandLine.arguments.contains("--check-display") {
    guard NSRunningApplication.runningApplications(withBundleIdentifier: "local.julian.WhitePoint").isEmpty else {
        print("Quit White Point normally before running display checks."); exit(1)
    }
    func difference(_ lhs: GammaTable, _ rhs: GammaTable) -> Float {
        let a = lhs.red + lhs.green + lhs.blue
        let b = rhs.red + rhs.green + rhs.blue
        guard a.count == b.count else { return .infinity }
        return zip(a, b).map { abs($0 - $1) }.max() ?? 0
    }
    do {
        let main = CGMainDisplayID()
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &displays, &count) == .success else {
            throw AppError.message("Could not enumerate displays for verification.")
        }
        let otherTables = try displays.prefix(Int(count)).filter { $0 != main }.map { try GammaTable(display: $0) }
        let table = try GammaTable(display: main)
        var testError: Error?
        do {
            for amount: Float in [0.35, 0.7, 0] {
                try table.write(amount: amount)
                let applied = try GammaTable(display: main)
                let original = table.red + table.green + table.blue
                let actual = applied.red + applied.green + applied.blue
                guard original.count == actual.count else { throw AppError.message("Display table size changed.") }
                let expected = original.map { soften($0, amount: amount) }
                let error = zip(expected, actual).map { abs($0 - $1) }.max() ?? 0
                guard error < 0.002 else { throw AppError.message("Display output differs from uniform reduction: \(error).") }
                print("PASS: main-display uniform table at intensity \(amount), maximum error \(error).")
                for other in otherTables {
                    let current = try GammaTable(display: other.display)
                    guard difference(other, current) < 0.002 else { throw AppError.message("Another display's table changed.") }
                }
            }
        } catch { testError = error }
        try table.write()
        let restored = try GammaTable(display: main)
        let restorationError = difference(table, restored)
        guard restorationError < 0.002 else { throw AppError.message("Display restoration differs: \(restorationError).") }
        print("PASS: restoration, maximum error \(restorationError); \(otherTables.count) other display(s) unchanged.")
        if let testError { throw testError }
    } catch { print(error.localizedDescription); exit(1) }

} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
