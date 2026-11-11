// Lists the Objective-C classes in CoreData that implement CloudKit mirroring, with their methods and
// ivars, and writes an lldb command file that disassembles every method of the interesting ones.
import CloudKit
import CoreData
import Foundation

@_cdecl("probeReady") @inline(never) public func probeReady() { print("ready") }

_ = NSPersistentCloudKitContainer.self
_ = CKContainer.self
guard let image = class_getImageName(NSManagedObjectContext.self).map({ String(cString: $0) }) else { fatalError("no image") }
print("IMAGE", image)
var count: UInt32 = 0
guard let names = objc_copyClassNamesForImage(image, &count) else { fatalError("no classes") }
let patterns = ["CloudKit", "NSCK", "Mirror", "PFCloud", "PFMirror"]
var commands: [String] = []
var all: [String] = []
for i in 0..<Int(count) {
    let name = String(cString: names[i])
    all.append(name)
    guard patterns.contains(where: { name.contains($0) }), let cls = NSClassFromString(name) else { continue }
    print("CLASS", name, "super:", class_getSuperclass(cls).map { NSStringFromClass($0) } ?? "-")
    var ivarCount: UInt32 = 0
    if let ivars = class_copyIvarList(cls, &ivarCount) {
        for j in 0..<Int(ivarCount) {
            let ivar = ivars[j]
            print("  ivar", ivar_getName(ivar).map { String(cString: $0) } ?? "?", ivar_getTypeEncoding(ivar).map { String(cString: $0) } ?? "")
        }
        free(ivars)
    }
    for (target, prefix) in [(cls, "-"), (object_getClass(cls)!, "+")] {
        var methodCount: UInt32 = 0
        guard let methods = class_copyMethodList(target, &methodCount) else { continue }
        for j in 0..<Int(methodCount) {
            let selector = NSStringFromSelector(method_getName(methods[j]))
            print("  \(prefix)[\(name) \(selector)]")
            commands.append("disassemble -n \"\(prefix)[\(name) \(selector)]\"")
        }
        free(methods)
    }
}
print("TOTAL CLASSES", count)
try! commands.joined(separator: "\n").write(toFile: "disassemble.lldb", atomically: true, encoding: .utf8)
print("COMMANDS", commands.count)
probeReady()
