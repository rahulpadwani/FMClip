// FMClip — FileMaker ⇄ XML text clipboard converter with a two-pane window.
// Build with build_fmclip.sh

import SwiftUI
import AppKit

// MARK: - FileMaker clipboard types

enum FMType: String, CaseIterable {
    case scripts = "XMSC"
    case steps = "XMSS"
    case functions = "XMFN"
    case fields = "XMFD"
    case tables = "XMTB"
    case valueLists = "XMVL"
    case layoutObjects = "XML2"

    var label: String {
        switch self {
        case .scripts: return "Scripts"
        case .steps: return "Script steps"
        case .functions: return "Custom functions"
        case .fields: return "Fields"
        case .tables: return "Tables"
        case .valueLists: return "Value lists"
        case .layoutObjects: return "Layout objects"
        }
    }

    /// Detects the FileMaker type from the first element inside <fmxmlsnippet>.
    static func detect(_ xml: String) -> FMType? {
        guard let r = xml.range(of: "<fmxmlsnippet") else { return nil }
        let after = xml[r.upperBound...]
        guard let gt = after.firstIndex(of: ">") else { return nil }
        let rest = after[after.index(after: gt)...]
        guard let lt = rest.firstIndex(of: "<") else { return nil }
        let name = String(rest[rest.index(after: lt)...].prefix { $0.isLetter || $0.isNumber })
        switch name {
        case "Step": return .steps
        case "Script", "Group": return .scripts
        case "CustomFunction": return .functions
        case "Field": return .fields
        case "BaseTable": return .tables
        case "ValueList": return .valueLists
        case "Layout": return .layoutObjects
        default: return nil
        }
    }
}

// MARK: - Clipboard bridge (uses osascript, same method that already works)

enum FMClipboard {
    static let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("fmclip.xml")

    static func runAS(_ src: String) -> (ok: Bool, out: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", src]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (false, error.localizedDescription) }
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (p.terminationStatus == 0, out)
    }

    /// Reads FileMaker data from the clipboard as XML text.
    static func readFileMaker() -> (FMType, String)? {
        try? FileManager.default.removeItem(at: tmp)
        var src = ""
        for t in FMType.allCases {
            src += "try\n"
            src += "set d to the clipboard as «class \(t.rawValue)»\n"
            src += "set f to open for access (POSIX file \"\(tmp.path)\") with write permission\n"
            src += "set eof f to 0\n"
            src += "write d to f\n"
            src += "close access f\n"
            src += "return \"\(t.rawValue)\"\n"
            src += "end try\n"
        }
        src += "return \"\""
        let r = runAS(src)
        guard r.ok,
              let t = FMType(rawValue: r.out),
              let text = try? String(contentsOf: tmp, encoding: .utf8)
        else { return nil }
        return (t, text)
    }

    /// Puts XML text on the clipboard as FileMaker data.
    static func writeFileMaker(_ xml: String, as t: FMType) -> Bool {
        do { try xml.write(to: tmp, atomically: true, encoding: .utf8) } catch { return false }
        let r = runAS("set the clipboard to (read (POSIX file \"\(tmp.path)\") as «class \(t.rawValue)»)")
        return r.ok
    }
}

// MARK: - Readable preview (FileMaker-style step list)

final class PreviewBuilder: NSObject, XMLParserDelegate {
    private(set) var lines: [String] = []
    private var indent = 0
    private var stack: [String] = []
    private var buf = ""
    private var stepName: String? = nil
    private var stepEnabled = true
    private var varName = ""
    private var text = ""
    private var firstCalc: String? = nil
    private var refName = ""
    private var fieldRef = ""

    static func build(_ xml: String) -> [String] {
        guard !xml.isEmpty, let data = xml.data(using: .utf8) else { return [] }
        let b = PreviewBuilder()
        let p = XMLParser(data: data)
        p.delegate = b
        p.parse()
        return b.lines
    }

    private func add(_ s: String) {
        lines.append(String(repeating: "    ", count: max(indent, 0)) + s)
    }

    private func clean(_ s: String) -> String {
        let one = s.components(separatedBy: .newlines).joined(separator: " ")
            .replacingOccurrences(of: "\t", with: " ")
        return one.count > 140 ? String(one.prefix(140)) + "…" : one
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes a: [String: String] = [:]) {
        stack.append(name)
        buf = ""
        if stepName == nil {
            switch name {
            case "Step":
                stepName = a["name"] ?? "?"
                stepEnabled = a["enable"] != "False"
                varName = ""; text = ""; firstCalc = nil; refName = ""; fieldRef = ""
            case "Script": add("📄 " + (a["name"] ?? "")); indent += 1
            case "Group": add("📁 " + (a["name"] ?? "")); indent += 1
            case "CustomFunction": add("ƒ " + (a["name"] ?? ""))
            case "Field": add("Field: " + (a["name"] ?? ""))
            case "BaseTable": add("Table: " + (a["name"] ?? ""))
            case "ValueList": add("Value list: " + (a["name"] ?? ""))
            default: break
            }
        } else {
            switch name {
            case "Script", "Layout":
                if refName.isEmpty { refName = a["name"] ?? "" }
            case "Field":
                if fieldRef.isEmpty {
                    let t = a["table"] ?? "", f = a["name"] ?? ""
                    fieldRef = t.isEmpty ? f : "\(t)::\(f)"
                }
            default: break
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { buf += string }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        buf += String(data: CDATABlock, encoding: .utf8) ?? ""
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                qualifiedName: String?) {
        if !stack.isEmpty { stack.removeLast() }
        if stepName != nil {
            switch name {
            case "Step": finishStep()
            case "Name": if stack.last == "Step" { varName = buf }
            case "Text": if stack.last == "Step" { text = buf }
            case "Calculation": if firstCalc == nil { firstCalc = buf }
            default: break
            }
        } else if name == "Script" || name == "Group" {
            indent = max(indent - 1, 0)
        }
        buf = ""
    }

    private func finishStep() {
        guard let n = stepName else { return }
        let calc = clean(firstCalc ?? "")
        let line: String
        switch n {
        case "# (comment)":
            line = text.isEmpty ? "" : "# " + clean(text)
        case "Set Variable":
            line = "Set Variable [ \(varName) ; Value: \(calc) ]"
        case "Perform Script":
            line = "Perform Script [ “\(refName)” " + (calc.isEmpty ? "]" : "; Parameter: \(calc) ]")
        case "Go to Layout", "New Window":
            line = refName.isEmpty ? n : "\(n) [ “\(refName)” ]"
        case "Set Field":
            line = "Set Field [ \(fieldRef) ; \(calc) ]"
        default:
            line = calc.isEmpty ? n : "\(n) [ \(calc) ]"
        }
        if ["Else If", "Else", "End If", "End Loop"].contains(n) { indent = max(indent - 1, 0) }
        add((stepEnabled ? "" : "// ") + line)
        if ["If", "Else If", "Else", "Loop"].contains(n) { indent += 1 }
        stepName = nil
    }
}

// MARK: - Model

final class Model: ObservableObject {
    @Published var xml: String = "" {
        didSet { if xml != oldValue { refresh() } }
    }
    @Published var preview: [String] = []
    @Published var type: FMType? = nil
    @Published var status = "Copy steps in FileMaker (⌘C) — they load here automatically."
    @Published var ok = true
    @Published var autoLoad = true
    private var lastChange = -1

    private func refresh() {
        type = FMType.detect(xml)
        preview = PreviewBuilder.build(xml)
    }

    private func say(_ s: String, ok: Bool) { status = s; self.ok = ok }

    func autoCheck() {
        guard autoLoad else { return }
        let cc = NSPasteboard.general.changeCount
        guard cc != lastChange else { return }
        lastChange = cc
        if let r = FMClipboard.readFileMaker() {
            xml = r.1
            say("Loaded \(r.0.label.lowercased()) from FileMaker.", ok: true)
        } else if let s = NSPasteboard.general.string(forType: .string), s.contains("<fmxmlsnippet") {
            xml = s
            say("Loaded FileMaker XML text from the clipboard.", ok: true)
        }
    }

    func pasteFromFileMaker() {
        lastChange = NSPasteboard.general.changeCount
        if let r = FMClipboard.readFileMaker() {
            xml = r.1
            say("Loaded \(r.0.label.lowercased()) from FileMaker.", ok: true)
        } else {
            say("No FileMaker data on the clipboard. Copy steps or scripts in FileMaker first.", ok: false)
        }
    }

    func copyForFileMaker() {
        guard !xml.isEmpty else { say("Nothing to copy — the text box is empty.", ok: false); return }
        guard let t = FMType.detect(xml) else {
            say("This isn't FileMaker XML (it must contain <fmxmlsnippet>).", ok: false); return
        }
        if FMClipboard.writeFileMaker(xml, as: t) {
            say("\(t.label) copied for FileMaker — press ⌘V in FileMaker.", ok: true)
        } else {
            say("Couldn't convert. Check the XML isn't broken.", ok: false)
        }
        lastChange = NSPasteboard.general.changeCount
    }

    func pasteText() {
        lastChange = NSPasteboard.general.changeCount
        guard let s = NSPasteboard.general.string(forType: .string), !s.isEmpty else {
            say("No text on the clipboard.", ok: false); return
        }
        xml = s
        say(FMType.detect(s) == nil ? "Pasted text, but it isn't FileMaker XML." : "Pasted XML text.",
            ok: FMType.detect(s) != nil)
    }

    func copyText() {
        guard !xml.isEmpty else { say("Nothing to copy — the text box is empty.", ok: false); return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(xml, forType: .string)
        lastChange = NSPasteboard.general.changeCount
        say("XML text copied — paste it anywhere.", ok: true)
    }

    func clear() {
        xml = ""
        say("Cleared.", ok: true)
    }
}

// MARK: - Plain-text editor (no smart quotes, so XML stays valid)

struct CodeEditor: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let sv = NSTextView.scrollableTextView()
        let tv = sv.documentView as! NSTextView
        tv.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.isRichText = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.allowsUndo = true
        tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.delegate = context.coordinator
        tv.string = text
        return sv
    }

    func updateNSView(_ sv: NSScrollView, context: Context) {
        guard let tv = sv.documentView as? NSTextView else { return }
        if tv.string != text { tv.string = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditor
        init(_ p: CodeEditor) { parent = p }
        func textDidChange(_ n: Notification) {
            guard let tv = n.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}

// MARK: - UI

struct ContentView: View {
    @EnvironmentObject var m: Model

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                leftPane
                Divider()
                rightPane
            }
            Divider()
            statusBar
        }
        .onAppear { m.autoCheck() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            m.autoCheck()
        }
    }

    private func paneTitle(_ title: String, _ sub: String) -> some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Text(sub).font(.caption).foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var leftPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            paneTitle("FileMaker", m.type.map { "\($0.label) · \(m.preview.count) lines" } ?? "Nothing loaded")
            Divider()
            ScrollView {
                Group {
                    if m.preview.isEmpty {
                        Text("Copy steps or scripts in FileMaker (⌘C).\nThey appear here automatically.")
                            .foregroundColor(.secondary)
                    } else {
                        Text(m.preview.joined(separator: "\n"))
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            .background(Color(nsColor: .textBackgroundColor))
            Divider()
            HStack {
                Button("Paste from FileMaker") { m.pasteFromFileMaker() }
                Spacer()
                Button("Copy for FileMaker") { m.copyForFileMaker() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .buttonStyle(.borderedProminent)
            }
            .padding(10)
        }
        .frame(minWidth: 380)
    }

    private var rightPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            paneTitle("Text (XML)", "\(m.xml.count) characters")
            Divider()
            CodeEditor(text: $m.xml)
            Divider()
            HStack {
                Button("Paste Text") { m.pasteText() }
                Button("Clear") { m.clear() }
                Spacer()
                Button("Copy Text") { m.copyText() }
                    .keyboardShortcut("c", modifiers: [.command, .option])
                    .buttonStyle(.borderedProminent)
            }
            .padding(10)
        }
        .frame(minWidth: 380)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Image(systemName: m.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(m.ok ? .green : .orange)
            Text(m.status).lineLimit(1)
            Spacer()
            Toggle("Auto-load clipboard", isOn: $m.autoLoad)
                .toggleStyle(.checkbox)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct FMClipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = Model()

    var body: some Scene {
        WindowGroup("FMClip") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 820, minHeight: 500)
        }
    }
}
