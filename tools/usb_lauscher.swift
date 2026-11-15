// usb_lauscher.swift – lückenloser, rein lesender USB-Beobachter für macOS.
//
// Statt ioreg alle 0,15 s abzufragen, lässt sich dieses Programm vom
// macOS-USB-System (IOKit) über JEDES An- und Abmelden eines USB-Geräts
// benachrichtigen. Auch ein Gerät, das nur Millisekunden da ist, wird erfasst,
// sofern macOS es überhaupt als Gerät anlegt.
//
// Es sendet nichts an die Kamera.
//
// Bauen:   swiftc -O usb_lauscher.swift -o usb_lauscher
// Starten: ./usb_lauscher          Beenden: Ctrl+C
// Protokoll: logs/lauscher_<Datum>.log neben dem Programm.

import Foundation
import IOKit
import IOKit.usb

// ---------- Ausgabe & Protokoll ----------

let zeitFormat: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f
}()

let programmOrdner: URL = {
    let pfad = Bundle.main.executablePath ?? CommandLine.arguments[0]
    return URL(fileURLWithPath: pfad).resolvingSymlinksInPath().deletingLastPathComponent()
}()

let logDatei: FileHandle? = {
    let ordner = programmOrdner.appendingPathComponent("logs")
    try? FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
    let stempel: String = {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd_HHmmss"; return f.string(from: Date())
    }()
    let url = ordner.appendingPathComponent("lauscher_\(stempel).log")
    FileManager.default.createFile(atPath: url.path, contents: nil)
    let h = FileHandle(forWritingAtPath: url.path)
    print("Protokoll: \(url.path)")
    return h
}()

func zeile(_ text: String, _ zeit: Date = Date()) {
    let s = "\(zeitFormat.string(from: zeit))  \(text)"
    print(s)
    fflush(stdout)
    if let h = logDatei, let d = (s + "\n").data(using: .utf8) {
        h.write(d)
        try? h.synchronize()
    }
}

// ---------- Gerätedaten ----------

func eigenschaft(_ s: io_service_t, _ key: String) -> Any? {
    IORegistryEntryCreateCFProperty(s, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
}

func zahl(_ s: io_service_t, _ key: String) -> Int {
    (eigenschaft(s, key) as? NSNumber)?.intValue ?? -1
}

func sonyHinweis(_ pid: Int) -> String {
    switch pid {
    case 0x0994: return "Sony Lademodus (USB Charger)"
    case 0x03e2: return "Sony UPDATER-MODUS  <<< wichtig!"
    case 0x08d3: return "Sony Kamera normal (a5000)  <<< wichtig!"
    default:     return "SONY, UNBEKANNTE ID  <<< wichtig!"
    }
}

struct Geraet {
    let text: String
    let seit: Date
    let sony: Bool
}

var geraete: [UInt64: Geraet] = [:]
var startPhase = true
var letzterSonyStart: Date?
var sonyAbstaende: [Double] = []
var sonyAnzahl = 0
var wichtigAnzahl = 0

func beschreibung(_ s: io_service_t) -> (String, Bool, Int) {
    let vid = zahl(s, "idVendor")
    let pid = zahl(s, "idProduct")
    let name = (eigenschaft(s, "USB Product Name") as? String)
        ?? (eigenschaft(s, "kUSBProductString") as? String) ?? "?"
    let ort = zahl(s, "locationID")
    var t = String(format: "%04x:%04x  %@  (Port 0x%08x)", vid & 0xffff, pid & 0xffff, name, ort)
    let sony = vid == 0x054c
    if sony { t += "  <== " + sonyHinweis(pid) }
    return (t, sony, pid)
}

func registryID(_ s: io_service_t) -> UInt64 {
    var id: UInt64 = 0
    IORegistryEntryGetRegistryEntryID(s, &id)
    return id
}

// ---------- Ereignisse ----------

func angemeldet(_ s: io_service_t) {
    let jetzt = Date()
    let (text, sony, pid) = beschreibung(s)
    geraete[registryID(s)] = Geraet(text: text, seit: jetzt, sony: sony)
    if startPhase {
        zeile("schon da:  " + text, jetzt)
        return
    }
    var zusatz = ""
    if sony {
        sonyAnzahl += 1
        if pid != 0x0994 { wichtigAnzahl += 1 }
        if let l = letzterSonyStart {
            let a = jetzt.timeIntervalSince(l)
            sonyAbstaende.append(a)
            zusatz = String(format: "   [%.2f s nach dem letzten Sony-Auftauchen]", a)
        }
        letzterSonyStart = jetzt
    }
    zeile("NEU:       " + text + zusatz, jetzt)
}

func abgemeldet(_ s: io_service_t) {
    let jetzt = Date()
    let id = registryID(s)
    if let g = geraete.removeValue(forKey: id) {
        let dauer = jetzt.timeIntervalSince(g.seit)
        zeile("WEG:       " + g.text + String(format: "   (war %.3f s da)", dauer), jetzt)
    } else {
        zeile("WEG:       " + beschreibung(s).0 + "   (Dauer unbekannt)", jetzt)
    }
}

func leeren(_ it: io_iterator_t, neu: Bool) {
    while true {
        let s = IOIteratorNext(it)
        if s == 0 { break }
        if neu { angemeldet(s) } else { abgemeldet(s) }
        IOObjectRelease(s)
    }
}

let rueckrufNeu: IOServiceMatchingCallback = { _, it in leeren(it, neu: true) }
let rueckrufWeg: IOServiceMatchingCallback = { _, it in leeren(it, neu: false) }

// ---------- Ende mit Zusammenfassung ----------

func beenden() -> Never {
    zeile("Beendet.")
    zeile("Sony-Auftauchen: \(sonyAnzahl), davon nicht Lademodus (wichtig): \(wichtigAnzahl)")
    if !sonyAbstaende.isEmpty {
        let sortiert = sonyAbstaende.sorted()
        let median = sortiert[sortiert.count / 2]
        zeile(String(format: "Abstände zwischen Sony-Auftauchen: Median %.2f s, min %.2f s, max %.2f s",
                     median, sortiert.first!, sortiert.last!))
    }
    exit(0)
}

signal(SIGINT, SIG_IGN)
signal(SIGTERM, SIG_IGN)
let signalQuellen: [DispatchSourceSignal] = [SIGINT, SIGTERM].map { sig in
    let q = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    q.setEventHandler { beenden() }
    q.resume()
    return q
}

// ---------- Start ----------

guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
    print("Fehler: IONotificationPortCreate fehlgeschlagen"); exit(1)
}
CFRunLoopAddSource(CFRunLoopGetCurrent(),
                   IONotificationPortGetRunLoopSource(port).takeUnretainedValue(),
                   .defaultMode)

var iterNeu: io_iterator_t = 0
var iterWeg: io_iterator_t = 0
let k1 = IOServiceAddMatchingNotification(port, kIOFirstMatchNotification,
                                          IOServiceMatching("IOUSBHostDevice"),
                                          rueckrufNeu, nil, &iterNeu)
let k2 = IOServiceAddMatchingNotification(port, kIOTerminatedNotification,
                                          IOServiceMatching("IOUSBHostDevice"),
                                          rueckrufWeg, nil, &iterWeg)
guard k1 == KERN_SUCCESS, k2 == KERN_SUCCESS else {
    print("Fehler beim Anmelden der Benachrichtigungen: \(k1) / \(k2)"); exit(1)
}

zeile("Lauscher gestartet (IOKit-Benachrichtigungen, keine Abfragelücken).")
leeren(iterNeu, neu: true)   // vorhandene Geräte auflisten und Benachrichtigung scharf schalten
leeren(iterWeg, neu: false)
startPhase = false
zeile("Bereit. Jetzt Kamera anstecken/einschalten. Beenden mit Ctrl+C.")

CFRunLoopRun()
