import CryptoKit
import Flutter
import Security
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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PureLiveSecretCipher") {
      FlutterMethodChannel(name: "pure_live/secret_cipher", binaryMessenger: registrar.messenger())
        .setMethodCallHandler(SecretCipher.shared.handle)
    }
    // Whether the clipboard has new text, without reading it (no "允许粘贴"
    // prompt; A18.1 c9): the pasteboard's change count, -1 without text.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PureLiveClipboard") {
      FlutterMethodChannel(name: "pure_live/clipboard", binaryMessenger: registrar.messenger())
        .setMethodCallHandler { call, result in
          guard call.method == "changeCount" else {
            result(FlutterMethodNotImplemented)
            return
          }
          let board = UIPasteboard.general
          result(board.hasStrings ? board.changeCount : -1)
        }
    }
  }
}

/// AES-256-GCM for the channel `pure_live/secret_cipher`
/// (`lib/platform/secret_cipher.dart`, `NativeChannelCipher`), like the
/// Android Keystore cipher: `seal` gives nonce, ciphertext and tag together,
/// `open` takes them back; the secret's name is the associated data. The key
/// is made once: on iOS it is kept in the Keychain (this device only), on
/// macOS — and on iOS when the Keychain refuses, as it can for re-signed
/// builds — in `secret.key` in the app's own Application Support folder.
final class SecretCipher {
  static let shared = SecretCipher()

  private var cached: SymmetricKey?
  private let service = "pure_live.secret_cipher"

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any], let ref = arguments["ref"] as? String else {
      result(FlutterError(code: "arguments", message: "ref is missing", details: nil))
      return
    }
    do {
      let aad = Data(ref.utf8)
      switch call.method {
      case "seal":
        guard let plain = arguments["plain"] as? String else { throw CipherError.arguments }
        let box = try AES.GCM.seal(Data(plain.utf8), using: try key(), authenticating: aad)
        guard let combined = box.combined else { throw CipherError.arguments }
        result(FlutterStandardTypedData(bytes: combined))
      case "open":
        guard let sealed = arguments["sealed"] as? FlutterStandardTypedData else { throw CipherError.arguments }
        let box = try AES.GCM.SealedBox(combined: sealed.data)
        let plain = try AES.GCM.open(box, using: try key(), authenticating: aad)
        result(String(decoding: plain, as: UTF8.self))
      default:
        result(FlutterMethodNotImplemented)
      }
    } catch {
      result(FlutterError(code: "cipher", message: "\(error)", details: nil))
    }
  }

  private enum CipherError: Error { case arguments, keyFile }

  private func key() throws -> SymmetricKey {
    if let known = cached { return known }
    #if os(iOS)
    if let data = keychainRead() { return remember(data) }
    #endif
    let url = try keyFileURL()
    if let data = try? Data(contentsOf: url) {
      guard data.count == 32 else { throw CipherError.keyFile }
      return remember(data)
    }
    let made = SymmetricKey(size: .bits256)
    let data = made.withUnsafeBytes { Data($0) }
    #if os(iOS)
    if keychainWrite(data) { return remember(data) }
    #endif
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    return remember(data)
  }

  private func remember(_ data: Data) -> SymmetricKey {
    let key = SymmetricKey(data: data)
    cached = key
    return key
  }

  private func keyFileURL() throws -> URL {
    let folder = try FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    #if os(macOS)
    // path_provider's application support folder on macOS adds the bundle id.
    let base = folder.appendingPathComponent(Bundle.main.bundleIdentifier ?? "pure_live", isDirectory: true)
    #else
    let base = folder
    #endif
    return base.appendingPathComponent("secret.key")
  }

  #if os(iOS)
  private var query: [String: Any] {
    [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "key"]
  }

  private func keychainRead() -> Data? {
    var found: [String: Any] = query
    found[kSecReturnData as String] = true
    found[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    guard SecItemCopyMatching(found as CFDictionary, &item) == errSecSuccess, let data = item as? Data,
      data.count == 32
    else { return nil }
    return data
  }

  private func keychainWrite(_ data: Data) -> Bool {
    var added: [String: Any] = query
    added[kSecValueData as String] = data
    added[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    return SecItemAdd(added as CFDictionary, nil) == errSecSuccess
  }
  #endif
}
