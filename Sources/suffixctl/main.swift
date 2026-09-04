import Foundation
import ConvertKit
import PDFKit

// A thin command-line front end to ConvertKit. The menu-bar app is the real
// product; this exists so the engine can be driven and tested without a UI.

func usage() -> Never {
    print("""
    usage:
      suffixctl inspect <file>            report the file's real format
      suffixctl plan <file>               what a conversion to its extension would do
      suffixctl convert <file> [--quality Q] [--scale S] [--no-backup]
                                          convert the file in place
      suffixctl watch <dir>... [--dry-run] react to renames as they happen
    """)
    exit(2)
}

var args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { usage() }
args.removeFirst()

var options = ConversionOptions()
var dryRun = false
var positional: [String] = []
var i = 0
while i < args.count {
    switch args[i] {
    case "--quality": i += 1; options.quality = Double(args[safe: i] ?? "") ?? options.quality
    case "--scale":   i += 1; options.rasterScale = Double(args[safe: i] ?? "") ?? options.rasterScale
    case "--no-backup": options.keepOriginal = false
    case "--dry-run": dryRun = true
    default: positional.append(args[i])
    }
    i += 1
}
guard let path = positional.first else { usage() }
let url = URL(fileURLWithPath: path).standardizedFileURL

if command == "watch" {
    let roots = positional.map { URL(fileURLWithPath: $0).standardizedFileURL }
    // Top-level `var`s are MainActor-isolated; the watcher callback is not.
    let isDry = dryRun
    let service = ConversionService(options: options)
    service.confirmLargeJobs = false          // no UI here to ask with
    let watcher = RenameWatcher(roots: roots) { renamed in
        switch service.decide(renamed) {
        case .ignore:
            break
        case .confirm(let plan), .convert(let plan):
            if isDry {
                print("would convert \(renamed.lastPathComponent): \(plan.summary)")
            } else {
                do {
                    let r = try service.perform(plan, on: renamed)
                    print("\(plan.summary)  →  \(r.finalURL.lastPathComponent)")
                } catch {
                    print("failed \(renamed.lastPathComponent): \(error.localizedDescription)")
                }
            }
            fflush(stdout)
        }
    }
    watcher.start()
    print("watching \(roots.map(\.path).joined(separator: ", "))")
    fflush(stdout)
    RunLoop.current.run()
    exit(0)
}

let actual = FileFormat.detect(at: url)

func makePlan() -> Result<ConversionPlan, ConversionPlan.Refusal> {
    ConversionPlan.make(source: actual, targetExtension: url.pathExtension) {
        PDFDocument(url: url)?.pageCount ?? 0
    }
}

func describe(_ refusal: ConversionPlan.Refusal) -> String {
    switch refusal {
    case .sameFormat(let f):             return "already a \(f.displayName) — nothing to do"
    case .unreadableSource:              return "not a file Rename can read"
    case .unwritableTarget(let f):       return "cannot write \(f.displayName)"
    case .unknownTargetExtension(let e): return "'.\(e)' isn't a format Rename converts to"
    }
}

switch command {
case "inspect":
    print(actual.map { "\(url.lastPathComponent): really a \($0.displayName)" }
          ?? "\(url.lastPathComponent): unrecognised")

case "plan":
    switch makePlan() {
    case .success(let plan): print(plan.summary + (plan.needsConfirmation ? "  [would ask first]" : ""))
    case .failure(let why):  print(describe(why)); exit(1)
    }

case "convert":
    switch makePlan() {
    case .failure(let why):
        print(describe(why)); exit(1)
    case .success(let plan):
        do {
            let result = try Converter(options: options).run(plan, on: url)
            print("\(plan.summary)  →  \(result.finalURL.lastPathComponent)")
            if let b = result.originalBackup { print("original kept at \(b.path)") }
        } catch {
            print("failed: \(error.localizedDescription)"); exit(1)
        }
    }

default:
    usage()
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
