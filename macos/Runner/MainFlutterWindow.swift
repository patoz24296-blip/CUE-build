import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var modelFolders: [URL] = []
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let storage = FlutterMethodChannel(name: "studio.cue/model-storage", binaryMessenger: flutterViewController.engine.binaryMessenger)
    storage.setMethodCallHandler { [weak self] call, result in
      guard call.method == "rememberDirectory" || call.method == "restoreDirectory" else {
        result(FlutterMethodNotImplemented); return
      }
      guard let self = self, let path = call.arguments as? String else {
        result(FlutterError(code: "invalid", message: "Choose a component folder again.", details: nil)); return
      }
      do {
        var bookmarks = UserDefaults.standard.dictionary(forKey: "cue-model-folders") as? [String: Data] ?? [:]
        var folder = URL(fileURLWithPath: path, isDirectory: true)
        if call.method == "restoreDirectory" {
          guard let bookmark = bookmarks[path] else { result(false); return }
          var stale = false
          folder = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
          guard folder.startAccessingSecurityScopedResource() else { result(false); return }
          self.modelFolders.append(folder)
          if stale {
            bookmarks[path] = try folder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
          }
        } else {
          bookmarks[path] = try folder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        UserDefaults.standard.set(bookmarks, forKey: "cue-model-folders")
        result(true)
      } catch {
        result(FlutterError(code: "storage", message: "Choose the component folder again to restore access.", details: nil))
      }
    }

    super.awakeFromNib()
  }
  deinit {
    for folder in modelFolders { folder.stopAccessingSecurityScopedResource() }
  }
}
