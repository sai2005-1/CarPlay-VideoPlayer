import Foundation
import CoreLocation
import Combine
import UIKit

/// Pure, testable logic that decides whether the vehicle is moving.
/// Moving starts as soon as speed exceeds the threshold; stopping requires the speed to stay
/// below half the threshold for `stopHoldSeconds` (prevents flicker at traffic lights).
struct MotionGate {
    var thresholdKmh: Double
    var stopHoldSeconds: Double = 3
    private(set) var isMoving = false
    private var belowSince: Date?

    init(thresholdKmh: Double, stopHoldSeconds: Double = 3) {
        self.thresholdKmh = thresholdKmh
        self.stopHoldSeconds = stopHoldSeconds
    }

    @discardableResult
    mutating func ingest(speedKmh: Double, at date: Date) -> Bool {
        guard speedKmh >= 0, speedKmh.isFinite else { return isMoving } // invalid reading
        if speedKmh > thresholdKmh {
            isMoving = true
            belowSince = nil
        } else if isMoving {
            if speedKmh < thresholdKmh * 0.5 {
                if let since = belowSince {
                    if date.timeIntervalSince(since) >= stopHoldSeconds {
                        isMoving = false
                        belowSince = nil
                    }
                } else {
                    belowSince = date
                }
            } else {
                belowSince = nil
            }
        }
        return isMoving
    }

    mutating func reset() {
        isMoving = false
        belowSince = nil
    }
}

/// Location (speed), battery and weather for the speed lock and overlay widgets.
final class SensorHub: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = SensorHub()

    @Published private(set) var speedKmh: Double = 0
    @Published private(set) var isMoving = false
    @Published private(set) var batteryLevel: Float = -1
    @Published private(set) var isCharging = false
    @Published private(set) var temperatureC: Double?
    @Published private(set) var weatherCode: Int?
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()
    private var gate: MotionGate
    private var lastWeatherFetch = Date.distantPast
    private var lastLocation: CLLocation?
    private var cancellables = Set<AnyCancellable>()
    private var isRunning = false

    override init() {
        gate = MotionGate(thresholdKmh: SettingsStore.shared.settings.speedThresholdKmh)
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        authorization = manager.authorizationStatus

        UIDevice.current.isBatteryMonitoringEnabled = true
        updateBattery()
        NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)
            .merge(with: NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateBattery() }
            .store(in: &cancellables)

        SettingsStore.shared.$settings
            .map(\.speedThresholdKmh)
            .removeDuplicates()
            .sink { [weak self] value in self?.gate.thresholdKmh = value }
            .store(in: &cancellables)
    }

    func requestAuthorizationIfNeeded() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func start() {
        requestAuthorizationIfNeeded()
        guard !isRunning else { return }
        isRunning = true
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            if Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes").flatMap({ $0 as? [String] })?.contains("location") == true {
                manager.allowsBackgroundLocationUpdates = true
                manager.showsBackgroundLocationIndicator = true
            }
            manager.startUpdatingLocation()
        }
    }

    func stop() {
        isRunning = false
        manager.stopUpdatingLocation()
        gate.reset()
        isMoving = false
        speedKmh = 0
    }

    private func updateBattery() {
        batteryLevel = UIDevice.current.batteryLevel
        let state = UIDevice.current.batteryState
        isCharging = state == .charging || state == .full
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorization = manager.authorizationStatus
            if self.isRunning {
                self.isRunning = false
                self.start()
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        DispatchQueue.main.async {
            self.lastLocation = loc
            if loc.speed >= 0 {
                let kmh = loc.speed * 3.6
                self.speedKmh = kmh
                let moving = self.gate.ingest(speedKmh: kmh, at: loc.timestamp)
                if moving != self.isMoving { self.isMoving = moving }
            }
            self.fetchWeatherIfNeeded(for: loc)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error)")
    }

    // MARK: Weather (Open-Meteo, no API key required)

    func fetchWeatherIfNeeded(for location: CLLocation? = nil) {
        guard let loc = location ?? lastLocation,
              Date().timeIntervalSince(lastWeatherFetch) > 15 * 60 else { return }
        guard SettingsStore.shared.settings.overlays.contains(where: { $0.kind == .weather && $0.enabled }) else { return }
        lastWeatherFetch = Date()
        let lat = String(format: "%.3f", loc.coordinate.latitude)
        let lon = String(format: "%.3f", loc.coordinate.longitude)
        guard let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,weather_code") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data,
                  let resp = try? JSONDecoder().decode(OpenMeteoResponse.self, from: data) else { return }
            DispatchQueue.main.async {
                self?.temperatureC = resp.current.temperature_2m
                self?.weatherCode = resp.current.weather_code
            }
        }.resume()
    }

    static func weatherSymbol(for code: Int?) -> String {
        guard let code = code else { return "cloud.sun" }
        switch code {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.sun"
        }
    }
}

private struct OpenMeteoResponse: Decodable {
    struct Current: Decodable {
        let temperature_2m: Double
        let weather_code: Int
    }
    let current: Current
}
