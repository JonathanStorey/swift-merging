# lldb script: for every CoreData function (blocks included) whose name matches the pattern, print the
# calls and literals it references, once each, in order.
import lldb, re, sys

PATTERN = re.compile(r"PFCloudKitImportRecordsWorkItem|PFCloudKitSerializer|PFCloudKitExporter|PFCloudKitExportContext|"
                     r"PFCloudKitImporter[ \]]|NSCloudKitMirroringDelegate (managedObjectContextSaved|remoteStoreDidChange|eventUpdated|exporter|_perform|_schedule|_finish|_request|_executeMirroringRequest)|"
                     r"NSCKRecordMetadata|NSCloudKitMirroringExportProgress|NSPersistentCloudKitContainerEvent |PFCloudKitHistoryAnalyzer")

def run(debugger, command, result, internal_dict):
    target = debugger.GetSelectedTarget()
    module = target.FindModule(lldb.SBFileSpec("CoreData"))
    seen = 0
    for i in range(module.GetNumSymbols()):
        symbol = module.GetSymbolAtIndex(i)
        name = symbol.GetName() or ""
        if symbol.GetType() != lldb.eSymbolTypeCode or not PATTERN.search(name):
            continue
        seen += 1
        print("FUNC " + name)
        printed = set()
        for inst in symbol.GetInstructions(target):
            comment = inst.GetComment(target)
            if not comment or comment in printed or "MergedGlobals" in comment or "___stack_chk" in comment:
                continue
            printed.add(comment)
            print("    " + comment[:220])
    print("FUNCTIONS %d" % seen)

def __lldb_init_module(debugger, internal_dict):
    debugger.HandleCommand("command script add -f calls.run calls")
