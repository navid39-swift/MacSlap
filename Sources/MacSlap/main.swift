// MacSlap — hit your MacBook, it makes a sound.
// Reads the undocumented Bosch IMU behind AppleSPUHIDDevice (Apple Silicon M2+ MacBooks).
// Easiest way to run:  ./run.sh   (builds, then starts with sudo)
//
// Sensor facts (from olvvier/apple-silicon-accelerometer):
//   - wake: set SensorPropertyReportingState=1, SensorPropertyPowerState=1, ReportInterval=1000 on AppleSPUHIDDriver
//   - accel device: AppleSPUHIDDevice with PrimaryUsagePage 0xFF00, PrimaryUsage 3
//   - 22-byte reports, x/y/z = Int32 little-endian at offsets 6/10/14, divide by 65536 -> g

import Foundation
import IOKit
import IOKit.hid
import AppKit

// MARK: - Config (command-line flags)

struct Config {
    var threshold = 0.15        // g of sudden change needed to count as a hit
    var cooldown = 0.35         // seconds between hits
    // Default: the "sounds" folder in the current directory, else the built-in macOS sounds
    var soundsDir = FileManager.default.fileExists(atPath: "sounds") ? "sounds" : "/System/Library/Sounds"
    var debug = false
    var overlap = false         // false = ignore hits until the current sound finishes
}

func parseArgs() -> Config {
    var c = Config()
    var args = CommandLine.arguments.dropFirst().makeIterator()
    while let a = args.next() {
        switch a {
        case "--threshold", "-t": if let v = args.next().flatMap(Double.init) { c.threshold = v }
        case "--cooldown", "-c":  if let v = args.next().flatMap(Double.init) { c.cooldown = v }
        case "--sounds", "-s":    if let v = args.next() { c.soundsDir = (v as NSString).expandingTildeInPath }
        case "--debug", "-d":     c.debug = true
        case "--overlap", "-o":   c.overlap = true
        case "--help", "-h":
            print("""
            Usage: sudo MacSlap [options]
              -t, --threshold <g>    hit sensitivity, lower = more sensitive (default 0.15)
              -c, --cooldown <sec>   min time between hits (default 0.35)
              -s, --sounds <dir>     folder of .wav/.mp3/.aiff/.m4a files (default: ./sounds)
              -d, --debug            print live acceleration spikes to help tune the threshold
              -o, --overlap          let new hits start a sound while one is still playing
            """)
            exit(0)
        default: print("Unknown option \(a) (try --help)")
        }
    }
    return c
}

let config = parseArgs()

// MARK: - Sound player

final class SoundBank {
    private var urls: [URL] = []
    private var playing: [NSSound] = []

    init(dir: String) {
        let exts: Set<String> = ["wav", "mp3", "aiff", "aif", "m4a", "caf"]
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        urls = files.sorted()
            .filter { exts.contains(($0 as NSString).pathExtension.lowercased()) }
            .map { URL(fileURLWithPath: dir).appendingPathComponent($0) }
        print("🔊 Loaded \(urls.count) sound(s) from \(dir)")
    }

    /// True while a sound is still playing.
    var isBusy: Bool { playing.contains { $0.isPlaying } }

    /// intensity 0...1 -> volume
    func play(intensity: Double) {
        guard let url = urls.randomElement(), let s = NSSound(contentsOf: url, byReference: true) else { return }
        s.volume = Float(0.3 + 0.7 * min(max(intensity, 0), 1))
        playing.removeAll { !$0.isPlaying }
        playing.append(s)
        s.play()
    }
}

let sounds = SoundBank(dir: config.soundsDir)

// MARK: - Hit detector

final class HitDetector {
    private var baseline = (x: 0.0, y: 0.0, z: 0.0)
    private var initialized = false
    private let start = Date()
    private var lastHit = Date.distantPast
    private var peakWindowEnd: Date?
    private var peak = 0.0
    private var hitCount = 0
    private var lastDebugPrint = Date.distantPast

    /// Called for every accelerometer sample (values in g).
    func process(x: Double, y: Double, z: Double) {
        let now = Date()
        if !initialized { baseline = (x, y, z); initialized = true; return }

        // Slow-moving average = gravity + tilt. Subtracting it leaves only sudden shocks.
        let a = 0.02
        baseline.x += a * (x - baseline.x)
        baseline.y += a * (y - baseline.y)
        baseline.z += a * (z - baseline.z)
        let dx = x - baseline.x, dy = y - baseline.y, dz = z - baseline.z
        let mag = (dx * dx + dy * dy + dz * dz).squareRoot()

        if now.timeIntervalSince(start) < 1.0 { return } // let the baseline settle

        if config.debug, mag > 0.03, now.timeIntervalSince(lastDebugPrint) > 0.05 {
            print(String(format: "   spike %.3f g", mag))
            lastDebugPrint = now
        }

        // Collecting the peak of a hit that already started
        if let end = peakWindowEnd {
            peak = max(peak, mag)
            if now >= end { fire(); peakWindowEnd = nil }
            return
        }

        // New hit?
        // Let the current sound finish completely unless --overlap was given.
        // Pushing lastHit forward also ignores the speaker's own vibration right after the sound ends.
        if !config.overlap, sounds.isBusy { lastHit = now; return }

        if mag > config.threshold, now.timeIntervalSince(lastHit) > config.cooldown {
            lastHit = now
            peak = mag
            peakWindowEnd = now.addingTimeInterval(0.03) // grab the strongest sample over 30 ms
        }
    }

    private func fire() {
        hitCount += 1
        // Map peak (threshold ... ~1.5 g) to 0...1
        let intensity = (peak - config.threshold) / max(1.5 - config.threshold, 0.01)
        let bar = String(repeating: "█", count: max(1, min(20, Int(intensity * 20))))
        print(String(format: "💥 Hit #%d  %.2f g  ", hitCount, peak) + bar)
        sounds.play(intensity: intensity) // already on the main run loop
    }
}

let detector = HitDetector()

// MARK: - IOKit sensor access

func forEachService(_ className: String, _ body: (io_service_t) -> Bool) {
    var iter: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iter) == KERN_SUCCESS else { return }
    defer { IOObjectRelease(iter) }
    var svc = IOIteratorNext(iter)
    while svc != 0 {
        let keepGoing = body(svc)
        IOObjectRelease(svc)
        if !keepGoing { return }
        svc = IOIteratorNext(iter)
    }
}

func intProperty(_ svc: io_service_t, _ key: String) -> Int? {
    IORegistryEntryCreateCFProperty(svc, key as CFString, kCFAllocatorDefault, 0)?
        .takeRetainedValue() as? Int
}

/// The SPU keeps the IMU asleep until asked to report.
func wakeSensors() {
    forEachService("AppleSPUHIDDriver") { svc in
        for (k, v) in [("SensorPropertyReportingState", 1), ("SensorPropertyPowerState", 1), ("ReportInterval", 1000)] {
            IORegistryEntrySetCFProperty(svc, k as CFString, NSNumber(value: Int32(v)))
        }
        return true
    }
}

func findAccelerometer() -> IOHIDDevice? {
    var found: IOHIDDevice?
    forEachService("AppleSPUHIDDevice") { svc in
        if intProperty(svc, "PrimaryUsagePage") == 0xFF00, intProperty(svc, "PrimaryUsage") == 3 {
            found = IOHIDDeviceCreate(kCFAllocatorDefault, svc)
            return false
        }
        return true
    }
    return found
}

// MARK: - Main

guard getuid() == 0 else {
    print("❌ Needs root to read the sensor. Run:  sudo \(CommandLine.arguments[0])")
    exit(1)
}

wakeSensors()

guard let device = findAccelerometer() else {
    print("❌ No accelerometer found. This needs an Apple Silicon MacBook (M2 or newer; M1 models lack it).")
    exit(1)
}

let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
guard openResult == kIOReturnSuccess else {
    print("❌ Couldn't open sensor (IOReturn \(openResult)).")
    exit(1)
}

let reportSize = 64
let reportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: reportSize)

IOHIDDeviceRegisterInputReportCallback(device, reportBuffer, reportSize, { _, result, _, _, _, report, length in
    guard result == kIOReturnSuccess, length >= 18 else { return }
    let raw = UnsafeRawPointer(report)
    let x = Double(Int32(littleEndian: raw.loadUnaligned(fromByteOffset: 6, as: Int32.self))) / 65536
    let y = Double(Int32(littleEndian: raw.loadUnaligned(fromByteOffset: 10, as: Int32.self))) / 65536
    let z = Double(Int32(littleEndian: raw.loadUnaligned(fromByteOffset: 14, as: Int32.self))) / 65536
    detector.process(x: x, y: y, z: z)
}, nil)

IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

print("👋 MacSlap is listening. Hit your MacBook! (threshold \(config.threshold) g, Ctrl+C to quit)")
if config.debug { print("   debug on: watch the spike values while you tap, then set --threshold just above normal typing") }

CFRunLoopRun()
