import AppKit
import CoreLocation

extension AppDelegate {
    func startScheduling() {
        WPObserveNightShift({ context in
            guard let context else { return }
            Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue().updateSchedule()
        }, Unmanaged.passUnretained(self).toOpaque())
        for name in [Notification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange, .NSCalendarDayChanged] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.updateSchedule() })
        }
        updateSchedule()
    }

    func updateSchedule() {
        scheduleTimer?.invalidate(); scheduleTimer = nil
        defer { scheduleWindowLabel?.stringValue = scheduleLabel.stringValue }
        let now = Date()
        var desired: Bool?
        var nextDate: Date?
        switch schedule.mode {
        case "scheduled":
            let evaluation = evaluateSchedule(schedule, now: now, calendar: .current)
            if let issue = evaluation.issue {
                scheduleLabel.stringValue = issue
                return
            }
            desired = evaluation.enabled
            if let until = overrideUntil, now < until {
                desired = nil
                scheduleLabel.stringValue = "Manual override until \(formatTime(until))."
            } else {
                overrideUntil = nil
                if let next = evaluation.next {
                    scheduleLabel.stringValue = "Scheduled \(next.enabled ? "on" : "off") at \(formatTime(next.date))."
                }
            }
            let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
            nextDate = min(evaluation.next?.date ?? midnight, midnight)
        case "nightshift":
            let state = WPNightShiftActive()
            if state < 0 {
                scheduleLabel.stringValue = "Night Shift status unavailable. Choose a time schedule."
            } else {
                let active = state == 1
                if lastNightShiftState != active { overrideNightShift = false }
                lastNightShiftState = active
                desired = overrideNightShift ? nil : active
                scheduleLabel.stringValue = overrideNightShift ? "Manual override until Night Shift changes." : "Following Night Shift: \(active ? "on" : "off")."
            }
            nextDate = now.addingTimeInterval(30)
        default:
            scheduleLabel.stringValue = "Schedule off."
            overrideUntil = nil; overrideNightShift = false; lastNightShiftState = nil
        }
        if let desired, desired != enabled {
            enabled = desired; defaults.set(enabled, forKey: "enabled"); apply()
        }
        if let nextDate {
            let timer = Timer(fire: nextDate, interval: 0, repeats: false) { [weak self] _ in self?.updateSchedule() }
            timer.tolerance = schedule.mode == "nightshift" ? 3 : 0.5
            RunLoop.main.add(timer, forMode: .common); scheduleTimer = timer
        }
    }

    func noteManualOverride() {
        if schedule.mode == "scheduled" {
            overrideUntil = evaluateSchedule(schedule, now: Date(), calendar: .current).next?.date
        } else if schedule.mode == "nightshift" {
            lastNightShiftState = WPNightShiftActive() == 1
            overrideNightShift = true
        }
    }

    func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.timeStyle = .short; formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    @objc func showSchedule() {
        stopRecording(); popover.performClose(nil)
        if let scheduleWindow { scheduleWindow.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 470, height: 490), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "White Point Schedule"; window.isReleasedWhenClosed = false
        scheduleWindow = window
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 22), stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -22), stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 22)])
        let title = NSTextField(labelWithString: "Schedule")
        title.font = .systemFont(ofSize: 20, weight: .semibold); stack.addArrangedSubview(title)
        modePicker = NSPopUpButton(); modePicker.addItems(withTitles: ["Off — manual control", "Custom schedule", "Follow Night Shift"])
        modePicker.selectItem(at: schedule.mode == "scheduled" ? 1 : schedule.mode == "nightshift" ? 2 : 0)
        modePicker.target = self; modePicker.action = #selector(scheduleEdited)
        stack.addArrangedSubview(modePicker)
        let preset = NSButton(title: "Use sunset → sunrise", target: self, action: #selector(sunsetPreset))
        stack.addArrangedSubview(preset)
        func row(_ title: String, endpoint: ScheduleEndpoint) -> (NSPopUpButton, NSDatePicker) {
            let row = NSStackView(); row.spacing = 10
            let label = NSTextField(labelWithString: title); label.widthAnchor.constraint(equalToConstant: 42).isActive = true
            row.addArrangedSubview(label)
            let picker = NSPopUpButton(); picker.addItems(withTitles: ScheduleEvent.allCases.map { $0.title })
            picker.selectItem(at: ScheduleEvent.allCases.firstIndex(of: endpoint.event)!)
            picker.target = self; picker.action = #selector(scheduleEdited); row.addArrangedSubview(picker)
            let time = NSDatePicker(); time.datePickerElements = [.hourMinute]; time.datePickerStyle = .textFieldAndStepper
            time.dateValue = Calendar.current.date(bySettingHour: endpoint.minute / 60, minute: endpoint.minute % 60, second: 0, of: Date())!
            time.target = self; time.action = #selector(scheduleEdited); row.addArrangedSubview(time)
            stack.addArrangedSubview(row)
            return (picker, time)
        }
        (onEventPicker, onTimePicker) = row("On", endpoint: schedule.on)
        (offEventPicker, offTimePicker) = row("Off", endpoint: schedule.off)
        stack.addArrangedSubview(NSTextField(labelWithString: "Location for sunrise and sunset"))
        let locationRow = NSStackView(); locationRow.spacing = 8
        latitudeField = NSTextField(); latitudeField.placeholderString = "Latitude"; latitudeField.widthAnchor.constraint(equalToConstant: 100).isActive = true
        longitudeField = NSTextField(); longitudeField.placeholderString = "Longitude"; longitudeField.widthAnchor.constraint(equalToConstant: 100).isActive = true
        if let location = schedule.location { latitudeField.doubleValue = location.latitude; longitudeField.doubleValue = location.longitude }
        locationRow.addArrangedSubview(latitudeField); locationRow.addArrangedSubview(longitudeField)
        locationRow.addArrangedSubview(NSButton(title: "Save location", target: self, action: #selector(saveLocation)))
        stack.addArrangedSubview(locationRow)
        stack.addArrangedSubview(NSButton(title: "Use current location…", target: self, action: #selector(requestCurrentLocation)))
        locationLabel = NSTextField(wrappingLabelWithString: schedule.location == nil ? "No location saved. Coordinates stay on this Mac." : "Location saved on this Mac.")
        locationLabel.font = .systemFont(ofSize: 11); locationLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(locationLabel)
        let info = NSTextField(wrappingLabelWithString: "Follow Night Shift matches its actual on/off state. Sun times are local estimates. Manual toggles last until the next scheduled change. The app must be running; enable Launch at login for daily use.")
        info.font = .systemFont(ofSize: 11); info.textColor = .secondaryLabelColor; stack.addArrangedSubview(info)
        let state = NSTextField(wrappingLabelWithString: scheduleLabel.stringValue)
        state.font = .systemFont(ofSize: 12, weight: .medium)
        scheduleWindowLabel = state; stack.addArrangedSubview(state)
        refreshScheduleControls()
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }

    func refreshScheduleControls() {
        guard modePicker != nil else { return }
        let custom = schedule.mode == "scheduled"
        onEventPicker.isEnabled = custom; offEventPicker.isEnabled = custom
        onTimePicker.isEnabled = custom && schedule.on.event == .time
        offTimePicker.isEnabled = custom && schedule.off.event == .time
    }

    @objc func scheduleEdited() {
        schedule.mode = ["manual", "scheduled", "nightshift"][modePicker.indexOfSelectedItem]
        schedule.on.event = ScheduleEvent.allCases[onEventPicker.indexOfSelectedItem]
        schedule.off.event = ScheduleEvent.allCases[offEventPicker.indexOfSelectedItem]
        let calendar = Calendar.current
        func minutes(_ date: Date) -> Int { calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date) }
        schedule.on.minute = minutes(onTimePicker.dateValue); schedule.off.minute = minutes(offTimePicker.dateValue)
        overrideUntil = nil; overrideNightShift = false; lastNightShiftState = nil
        schedule.save(defaults); refreshScheduleControls(); updateSchedule()
    }

    @objc func sunsetPreset() {
        modePicker.selectItem(at: 1)
        onEventPicker.selectItem(at: ScheduleEvent.allCases.firstIndex(of: .sunset)!)
        offEventPicker.selectItem(at: ScheduleEvent.allCases.firstIndex(of: .sunrise)!)
        scheduleEdited()
    }

    @objc func saveLocation() {
        guard let latitude = Double(latitudeField.stringValue), let longitude = Double(longitudeField.stringValue), SolarLocation(latitude: latitude, longitude: longitude).isValid else {
            locationLabel.stringValue = "Enter latitude −90…90 and longitude −180…180."; return
        }
        schedule.location = SolarLocation(latitude: latitude, longitude: longitude)
        schedule.save(defaults); overrideUntil = nil
        locationLabel.stringValue = "Location saved on this Mac."; updateSchedule()
    }

    @objc func requestCurrentLocation() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        requestingLocation = true
        locationLabel.stringValue = "Requesting your location…"
        switch locationManager.authorizationStatus {
        case .notDetermined: locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            requestingLocation = false; locationLabel.stringValue = "Location access is off. Enter coordinates or allow White Point in Location Services."
        default: locationManager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard requestingLocation else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        case .denied, .restricted:
            requestingLocation = false; locationLabel.stringValue = "Location access is off. You can enter coordinates instead."
        default: break
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0 else { return }
        requestingLocation = false
        latitudeField.doubleValue = location.coordinate.latitude; longitudeField.doubleValue = location.coordinate.longitude
        saveLocation()
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        requestingLocation = false
        locationLabel.stringValue = "Could not get your location. Enter coordinates or try again."
    }
}
