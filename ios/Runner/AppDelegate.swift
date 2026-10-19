import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, UIDocumentPickerDelegate {
  private var exportResult: FlutterResult?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "studio.cue/export", binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { [weak self, weak controller] call, result in
        guard call.method == "exportRecording" else { result(FlutterMethodNotImplemented); return }
        guard let self = self, let controller = controller,
              let arguments = call.arguments as? [String: Any], let path = arguments["path"] as? String else {
          result(FlutterError(code: "invalid", message: "Recording is unavailable.", details: nil)); return
        }
        let file = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        let home = URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().path
        guard file.path.hasPrefix(home + "/"), FileManager.default.fileExists(atPath: file.path), self.exportResult == nil else {
          result(FlutterError(code: "unavailable", message: "This recording cannot be exported right now.", details: nil)); return
        }
        self.exportResult = result
        let picker = UIDocumentPickerViewController(forExporting: [file], asCopy: true)
        picker.delegate = self
        controller.present(picker, animated: true)
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    exportResult?(true); exportResult = nil
  }
  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    exportResult?(false); exportResult = nil
  }
}
