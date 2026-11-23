import CryptoKit
import DeviceCheck
import Flutter
import Security
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = self.registrar(forPlugin: "DmbDeviceIdentity") {
      DeviceIdentityPlugin.register(with: registrar)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

/// Device identity and Secure Enclave device key (audit DID-01..DID-04).
///
/// Identifier: "ios-" + a random 128-bit UUID (v4) generated once and stored in the
/// Keychain with kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly (never synced to
/// iCloud, never restored to another device). A Keychain read failure is reported as
/// an error (KEYCHAIN_LOCKED / KEYCHAIN_UNAVAILABLE); a new UUID is created ONLY when the
/// item does not exist (errSecItemNotFound). identifierForVendor is not used.
///
/// Key: ECDSA P-256 generated inside the Secure Enclave (kSecAttrTokenIDSecureEnclave);
/// the private key cannot be exported. There is no software fallback: without a
/// Secure Enclave (e.g. Simulator) the error SECURE_ENCLAVE_UNAVAILABLE is returned and
/// the device stays on the legacy binding until the bank's policy says otherwise.
final class DeviceIdentityPlugin: NSObject {
  static let channelName = "com.bprdmb.mbanking/device_identity"
  private static let service = "com.bprdmb.mbanking.device-identity"
  private static let account = "device_id_v1"
  private static let tagPrefix = "com.bprdmb.mbanking."
  /// ASN.1 SubjectPublicKeyInfo header for an uncompressed P-256 point (65 bytes follow).
  private static let spkiHeader: [UInt8] = [
    0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01,
    0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00,
  ]

  private struct Failure: Error {
    let code: String
    let message: String
  }

  private let queue = DispatchQueue(label: "com.bprdmb.mbanking.device-identity")

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    let instance = DeviceIdentityPlugin()
    channel.setMethodCallHandler { call, result in
      instance.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    queue.async {
      do {
        let reply: Any
        switch call.method {
        case "getDeviceIdentity":
          reply = try self.identity()
        case "getKeyInfo":
          reply = try self.keyInfo(try self.alias(args))
        case "generateKey":
          reply = try self.generateKey(try self.alias(args))
        case "sign":
          reply = try self.sign(try self.alias(args), message: args?["message"] as? String)
        case "appAttestSupported":
          reply = self.appAttestSupported()
        case "appAttestGenerateKey":
          reply = try self.appAttestGenerateKey(try self.alias(args))
        case "appAttestAttest":
          reply = try self.appAttestAttest(try self.alias(args), message: args?["message"] as? String)
        case "appAttestAssert":
          reply = try self.appAttestAssert(try self.alias(args), message: args?["message"] as? String)
        case "appAttestKeyInfo":
          reply = try self.appAttestKeyInfo(try self.alias(args))
        case "resetCorruptDeviceIdentity":
          reply = try self.resetCorruptDeviceIdentity()
        case "deleteKey":
          try self.deleteKey(try self.alias(args))
          reply = true
        default:
          DispatchQueue.main.async { result(FlutterMethodNotImplemented) }
          return
        }
        DispatchQueue.main.async { result(reply) }
      } catch let failure as Failure {
        DispatchQueue.main.async {
          result(FlutterError(code: failure.code, message: failure.message, details: nil))
        }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "KEYCHAIN_ERROR", message: String(describing: type(of: error)), details: nil))
        }
      }
    }
  }

  private func alias(_ args: [String: Any]?) throws -> String {
    guard let alias = args?["alias"] as? String,
      alias.range(of: "^dmb_device_key_[a-z0-9_]{1,40}$", options: .regularExpression) != nil
    else {
      throw Failure(code: "INVALID_ARGUMENT", message: "Alias kunci tidak valid")
    }
    return alias
  }

  private static func keychainFailure(_ status: OSStatus, _ operation: String) -> Failure {
    if status == errSecInteractionNotAllowed {
      return Failure(code: "KEYCHAIN_LOCKED", message: "Keychain belum dapat diakses (perangkat terkunci)")
    }
    return Failure(code: "KEYCHAIN_UNAVAILABLE", message: "\(operation) gagal (status \(status))")
  }

  // MARK: - Identity

  private func identity() throws -> [String: Any] {
    return ["device_id": "ios-" + (try Self.readOrCreateDeviceId()), "platform": "ios"]
  }

  private static func readDeviceId() throws -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound {
      return nil
    }
    guard status == errSecSuccess else {
      throw keychainFailure(status, "Membaca identitas perangkat")
    }
    guard let data = item as? Data, let value = String(data: data, encoding: .utf8),
      let uuid = UUID(uuidString: value), uuid.uuidString.lowercased() == value
    else {
      // Never replaced silently: a corrupt identity must be investigated.
      throw Failure(code: "DEVICE_ID_CORRUPT", message: "Identitas perangkat di Keychain tidak valid")
    }
    return value
  }

  private static func readOrCreateDeviceId() throws -> String {
    if let existing = try readDeviceId() {
      return existing
    }
    let value = UUID().uuidString.lowercased()  // random (version 4), 122 random bits
    let add: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecValueData as String: Data(value.utf8),
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    let status = SecItemAdd(add as CFDictionary, nil)
    if status == errSecSuccess {
      return value
    }
    if status == errSecDuplicateItem, let existing = try readDeviceId() {
      return existing  // created concurrently
    }
    throw keychainFailure(status, "Menyimpan identitas perangkat")
  }

  /// L2 (explicit recovery, never automatic): replaces an identity whose Keychain value is
  /// present but corrupt. The new identifier is unbound on the server, so the customer
  /// must re-bind through OTP (Lupa Password). Read failures (locked/unavailable Keychain)
  /// never reach this path.
  private func resetCorruptDeviceIdentity() throws -> [String: Any] {
    var corrupt = false
    do {
      _ = try Self.readDeviceId()
    } catch let failure as Failure where failure.code == "DEVICE_ID_CORRUPT" {
      corrupt = true
    }
    // SECURITY: only a present-but-invalid value is replaced; a readable identity or a
    // locked / unavailable Keychain never produces a new identifier.
    guard corrupt else {
      throw Failure(code: "DEVICE_ID_NOT_CORRUPT", message: "Identitas perangkat tidak rusak")
    }
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.service,
      kSecAttrAccount as String: Self.account,
    ]
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw Self.keychainFailure(status, "Menghapus identitas rusak")
    }
    return try identity()
  }

  // MARK: - App Attest (iOS 14+): the Apple-attested key is the binding key

  private func appAttestSupported() -> Bool {
    if #available(iOS 14.0, *) {
      return DCAppAttestService.shared.isSupported
    }
    return false
  }

  private func appAttestAccount(_ alias: String) -> String {
    return "appattest." + alias
  }

  private func storeAppAttestKeyId(_ alias: String, _ keyId: String) throws {
    let base: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.service,
      kSecAttrAccount as String: appAttestAccount(alias),
    ]
    let deleteStatus = SecItemDelete(base as CFDictionary)
    guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
      throw Self.keychainFailure(deleteStatus, "Mengganti kunci App Attest")
    }
    var add = base
    add[kSecValueData as String] = Data(keyId.utf8)
    add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let status = SecItemAdd(add as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw Self.keychainFailure(status, "Menyimpan kunci App Attest")
    }
  }

  private func storedAppAttestKeyId(_ alias: String) throws -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.service,
      kSecAttrAccount as String: appAttestAccount(alias),
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound {
      return nil
    }
    guard status == errSecSuccess, let data = item as? Data, let keyId = String(data: data, encoding: .utf8) else {
      throw Self.keychainFailure(status, "Membaca kunci App Attest")
    }
    return keyId
  }

  private func clientDataHash(_ message: String?) throws -> Data {
    guard let encoded = message, let data = Data(base64Encoded: encoded), !data.isEmpty else {
      throw Failure(code: "INVALID_ARGUMENT", message: "Pesan tidak valid")
    }
    return Data(SHA256.hash(data: data))
  }

  /// Waits for a DeviceCheck completion handler (called on the plugin's background queue).
  private func waitFor<T>(_ start: (@escaping (T?, Error?) -> Void) -> Void) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    var value: T?
    var failure: Error?
    start { v, e in
      value = v
      failure = e
      semaphore.signal()
    }
    if semaphore.wait(timeout: .now() + 30) == .timedOut {
      throw Failure(code: "APP_ATTEST_TIMEOUT", message: "App Attest tidak merespons")
    }
    if let error = failure as NSError? {
      if error.domain == DCErrorDomain && error.code == DCError.Code.invalidKey.rawValue {
        throw Failure(code: "KEY_NOT_FOUND", message: "Kunci App Attest tidak berlaku lagi")
      }
      throw Failure(code: "APP_ATTEST_FAILED", message: "\(error.domain) \(error.code)")
    }
    guard let result = value else {
      throw Failure(code: "APP_ATTEST_FAILED", message: "App Attest tidak mengembalikan hasil")
    }
    return result
  }

  private func appAttestGenerateKey(_ alias: String) throws -> [String: Any] {
    guard #available(iOS 14.0, *), DCAppAttestService.shared.isSupported else {
      throw Failure(code: "APP_ATTEST_UNSUPPORTED", message: "App Attest tidak tersedia di perangkat ini")
    }
    // A new key per enrollment (App Attest keys are never reused or exported).
    let keyId: String = try waitFor { done in DCAppAttestService.shared.generateKey(completionHandler: done) }
    try storeAppAttestKeyId(alias, keyId)
    return ["key_id": keyId]
  }

  private func appAttestAttest(_ alias: String, message: String?) throws -> [String: Any] {
    guard #available(iOS 14.0, *), DCAppAttestService.shared.isSupported else {
      throw Failure(code: "APP_ATTEST_UNSUPPORTED", message: "App Attest tidak tersedia di perangkat ini")
    }
    guard let keyId = try storedAppAttestKeyId(alias) else {
      throw Failure(code: "KEY_NOT_FOUND", message: "Kunci App Attest belum dibuat")
    }
    let hash = try clientDataHash(message)
    let attestation: Data = try waitFor { done in
      DCAppAttestService.shared.attestKey(keyId, clientDataHash: hash, completionHandler: done)
    }
    return ["key_id": keyId, "attestation_object": attestation.base64EncodedString()]
  }

  private func appAttestAssert(_ alias: String, message: String?) throws -> String {
    guard #available(iOS 14.0, *), DCAppAttestService.shared.isSupported else {
      throw Failure(code: "APP_ATTEST_UNSUPPORTED", message: "App Attest tidak tersedia di perangkat ini")
    }
    guard let keyId = try storedAppAttestKeyId(alias) else {
      throw Failure(code: "KEY_NOT_FOUND", message: "Kunci App Attest tidak ditemukan")
    }
    let hash = try clientDataHash(message)
    let assertion: Data = try waitFor { done in
      DCAppAttestService.shared.generateAssertion(keyId, clientDataHash: hash, completionHandler: done)
    }
    return assertion.base64EncodedString()
  }

  private func appAttestKeyInfo(_ alias: String) throws -> [String: Any] {
    guard let keyId = try storedAppAttestKeyId(alias) else {
      return ["exists": false]
    }
    return ["exists": true, "key_id": keyId]
  }

  // MARK: - Secure Enclave key

  private func tag(_ alias: String) -> Data {
    return Data((Self.tagPrefix + alias).utf8)
  }

  private func findKey(_ alias: String) throws -> SecKey? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassKey,
      kSecAttrApplicationTag as String: tag(alias),
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecReturnRef as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound {
      return nil
    }
    guard status == errSecSuccess, let ref = item, CFGetTypeID(ref) == SecKeyGetTypeID() else {
      throw Self.keychainFailure(status, "Membaca kunci perangkat")
    }
    return (ref as! SecKey)
  }

  private func describe(_ privateKey: SecKey) throws -> [String: Any] {
    var error: Unmanaged<CFError>?
    guard let publicKey = SecKeyCopyPublicKey(privateKey),
      let raw = SecKeyCopyExternalRepresentation(publicKey, &error) as Data?, raw.count == 65
    else {
      throw Failure(code: "KEYCHAIN_ERROR", message: "Kunci publik tidak dapat dibaca")
    }
    let attributes = SecKeyCopyAttributes(privateKey) as? [String: Any]
    let token = attributes?[kSecAttrTokenID as String] as? String
    let level = token == (kSecAttrTokenIDSecureEnclave as String) ? "SECURE_ENCLAVE" : "SOFTWARE"
    var spki = Data(Self.spkiHeader)
    spki.append(raw)
    return ["exists": true, "public_key": spki.base64EncodedString(), "security_level": level]
  }

  private func keyInfo(_ alias: String) throws -> [String: Any] {
    guard let key = try findKey(alias) else {
      return ["exists": false]
    }
    return try describe(key)
  }

  private func generateKey(_ alias: String) throws -> [String: Any] {
    #if targetEnvironment(simulator)
      throw Failure(code: "SECURE_ENCLAVE_UNAVAILABLE", message: "Simulator tidak memiliki Secure Enclave")
    #else
      try deleteKey(alias)  // a fresh key per enrollment: public keys are never reused
      var error: Unmanaged<CFError>?
      guard
        let access = SecAccessControlCreateWithFlags(
          // DB-M5: the key signs only while the device is unlocked.
          kCFAllocatorDefault, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .privateKeyUsage, &error)
      else {
        throw Failure(code: "SECURE_ENCLAVE_UNAVAILABLE", message: "Kontrol akses kunci tidak dapat dibuat")
      }
      let attributes: [String: Any] = [
        kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
        kSecAttrKeySizeInBits as String: 256,
        kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
        kSecPrivateKeyAttrs as String: [
          kSecAttrIsPermanent as String: true,
          kSecAttrApplicationTag as String: tag(alias),
          kSecAttrAccessControl as String: access,
        ],
      ]
      guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
        throw Failure(code: "SECURE_ENCLAVE_UNAVAILABLE", message: "Secure Enclave tidak dapat membuat kunci")
      }
      let info = try describe(key)
      guard info["security_level"] as? String == "SECURE_ENCLAVE" else {
        try deleteKey(alias)
        throw Failure(code: "INSECURE_HARDWARE", message: "Kunci tidak berada di Secure Enclave")
      }
      return info
    #endif
  }

  private func sign(_ alias: String, message: String?) throws -> String {
    guard let encoded = message, let data = Data(base64Encoded: encoded), !data.isEmpty else {
      throw Failure(code: "INVALID_ARGUMENT", message: "Pesan tidak valid")
    }
    guard let key = try findKey(alias) else {
      throw Failure(code: "KEY_NOT_FOUND", message: "Kunci perangkat tidak ditemukan")
    }
    let algorithm = SecKeyAlgorithm.ecdsaSignatureMessageX962SHA256  // DER (r, s), SHA-256
    guard SecKeyIsAlgorithmSupported(key, .sign, algorithm) else {
      throw Failure(code: "KEYCHAIN_ERROR", message: "Algoritma tanda tangan tidak didukung")
    }
    var error: Unmanaged<CFError>?
    guard let signature = SecKeyCreateSignature(key, algorithm, data as CFData, &error) as Data? else {
      throw Failure(code: "SIGN_FAILED", message: "Tanda tangan perangkat gagal dibuat")
    }
    return signature.base64EncodedString()
  }

  private func deleteKey(_ alias: String) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassKey,
      kSecAttrApplicationTag as String: tag(alias),
    ]
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw Self.keychainFailure(status, "Menghapus kunci perangkat")
    }
  }
}
