import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // The share popup with a Copy link action, which share_plus cannot add
    // (lib/features/itineraries/data/share_service.dart is the Dart side).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NtripiShareLink") {
      ShareLinkChannel.register(with: registrar.messenger())
    }
  }
}

/// Answers "ntripi/share": the share popup for a shared trip or profile, with
/// one action added — Copy link, the link alone. Other apps, and the popup's
/// own Copy, still get the caption and the link.
enum ShareLinkChannel {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "ntripi/share", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "share",
        let args = call.arguments as? [String: Any],
        let text = args["text"] as? String,
        let url = args["url"] as? String
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let presenter = topViewController() else {
        result(FlutterError(code: "no_view", message: "Nothing to show the share popup over", details: nil))
        return
      }
      let copyLink = CopyLinkActivity(url: url, title: args["copyLinkLabel"] as? String ?? "Copy link")
      let popup = UIActivityViewController(
        activityItems: [ShareTextItem(text: text, subject: args["subject"] as? String ?? "")],
        applicationActivities: [copyLink]
      )
      // An iPad shows the popup as a popover, which must point at something:
      // the Share button that was tapped.
      if let popover = popup.popoverPresentationController {
        popover.sourceView = presenter.view
        if let origin = args["origin"] as? [Double], origin.count == 4 {
          popover.sourceRect = CGRect(x: origin[0], y: origin[1], width: origin[2], height: origin[3])
        } else {
          popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
          popover.permittedArrowDirections = []
        }
      }
      // The app says "Link copied": nothing on iOS confirms a copy.
      popup.completionWithItemsHandler = { type, completed, _, _ in
        result(completed && type == CopyLinkActivity.type ? "copiedLink" : nil)
      }
      presenter.present(popup, animated: true)
    }
  }

  private static func topViewController() -> UIViewController? {
    let window = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
    var top = window?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }
}

/// The popup's Copy link: puts the link alone on the pasteboard.
final class CopyLinkActivity: UIActivity {
  static let type = UIActivity.ActivityType("app.ntripi.copy-link")

  private let url: String
  private let title: String

  init(url: String, title: String) {
    self.url = url
    self.title = title
    super.init()
  }

  // Listed with Copy and the other actions, not among the apps.
  override class var activityCategory: UIActivity.Category { .action }
  override var activityType: UIActivity.ActivityType? { Self.type }
  override var activityTitle: String? { title }
  override var activityImage: UIImage? { UIImage(systemName: "link") }

  override func canPerform(withActivityItems activityItems: [Any]) -> Bool { true }

  override func perform() {
    UIPasteboard.general.string = url
    activityDidFinish(true)
  }
}

/// The caption and the link, plus the subject Mail puts in its subject line.
final class ShareTextItem: NSObject, UIActivityItemSource {
  private let text: String
  private let subject: String

  init(text: String, subject: String) {
    self.text = text
    self.subject = subject
  }

  func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
    text
  }

  func activityViewController(
    _ activityViewController: UIActivityViewController,
    itemForActivityType activityType: UIActivity.ActivityType?
  ) -> Any? {
    text
  }

  func activityViewController(
    _ activityViewController: UIActivityViewController,
    subjectForActivityType activityType: UIActivity.ActivityType?
  ) -> String {
    subject
  }
}
