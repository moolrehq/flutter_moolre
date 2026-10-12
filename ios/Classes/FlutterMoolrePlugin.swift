import Flutter
import UIKit
import WebKit

/// Opens Moolre's hosted payment page in a WKWebView.
public class FlutterMoolrePlugin: NSObject, FlutterPlugin {
  private var pending: FlutterResult?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "flutter_moolre/hosted_checkout",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(FlutterMoolrePlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "open" else {
      result(FlutterMethodNotImplemented)
      return
    }
    let args = call.arguments as? [String: Any]
    guard let rawUrl = args?["url"] as? String,
          let url = URL(string: rawUrl),
          url.scheme == "https",
          let returnUrl = args?["returnUrl"] as? String
    else {
      result(FlutterError(code: "INVALID_ARGUMENTS", message: "A secure checkout URL is required.", details: nil))
      return
    }
    guard pending == nil else {
      result(FlutterError(code: "ALREADY_OPEN", message: "Checkout is already open.", details: nil))
      return
    }
    guard let presenter = Self.topViewController() else {
      result(FlutterError(code: "NO_VIEW_CONTROLLER", message: "Checkout needs a visible screen.", details: nil))
      return
    }
    pending = result
    let checkout = MoolreCheckoutViewController(
      url: url,
      returnUrl: returnUrl,
      title: args?["title"] as? String ?? "Moolre checkout"
    ) { [weak self] event in
      self?.pending?(["event": event])
      self?.pending = nil
    }
    let navigation = UINavigationController(rootViewController: checkout)
    navigation.presentationController?.delegate = checkout
    presenter.present(navigation, animated: true)
  }

  private static func topViewController() -> UIViewController? {
    var window: UIWindow?
    if #available(iOS 13.0, *) {
      window = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .first { $0.isKeyWindow }
    }
    var top = (window ?? UIApplication.shared.delegate?.window ?? nil)?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }
}

final class MoolreCheckoutViewController: UIViewController, WKNavigationDelegate,
  UIAdaptivePresentationControllerDelegate
{
  private let url: URL
  private let returnUrl: String
  private let onFinish: (String) -> Void
  private var finished = false
  private var closing = false
  private let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())

  init(url: URL, returnUrl: String, title: String, onFinish: @escaping (String) -> Void) {
    self.url = url
    self.returnUrl = returnUrl
    self.onFinish = onFinish
    super.init(nibName: nil, bundle: nil)
    self.title = title
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override func viewDidLoad() {
    super.viewDidLoad()
    let closeItem: UIBarButtonItem.SystemItem
    if #available(iOS 13.0, *) {
      closeItem = .close
    } else {
      closeItem = .cancel
    }
    navigationItem.leftBarButtonItem = UIBarButtonItem(
      barButtonSystemItem: closeItem,
      target: self,
      action: #selector(closeTapped)
    )
    webView.navigationDelegate = self
    webView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(webView)
    NSLayoutConstraint.activate([
      webView.topAnchor.constraint(equalTo: view.topAnchor),
      webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
    ])
    webView.load(URLRequest(url: url))
  }

  @objc private func closeTapped() { finish("closed") }

  func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    guard let target = navigationAction.request.url else {
      decisionHandler(.allow)
      return
    }
    if target.absoluteString.hasPrefix(returnUrl) {
      decisionHandler(.cancel)
      finish("redirected")
      return
    }
    if target.scheme == "https" || target.scheme == "http" || target.scheme == "about" {
      decisionHandler(.allow)
      return
    }
    // tel:, mailto: and wallet-app links open outside the page.
    decisionHandler(.cancel)
    UIApplication.shared.open(target)
  }

  // Swipe-to-dismiss on iOS 13+ sheets.
  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    complete("closed")
  }

  private func finish(_ event: String) {
    guard !finished, !closing else { return }
    closing = true
    dismiss(animated: true) { [weak self] in self?.complete(event) }
  }

  private func complete(_ event: String) {
    guard !finished else { return }
    finished = true
    webView.stopLoading()
    webView.navigationDelegate = nil
    onFinish(event)
  }
}
