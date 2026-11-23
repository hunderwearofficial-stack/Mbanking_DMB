package com.example.m_banking_bpr

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.Signature
import java.security.spec.ECGenParameterSpec
import java.util.concurrent.Executors

/**
 * Device identity and hardware-backed device key (audit DID-01..DID-04).
 *
 * Identifier: "and-" + the full 64-bit Settings.Secure.ANDROID_ID (16 lowercase hex).
 * Since Android 8 the value is scoped to (app signing key, user, device): stable across
 * app restarts, updates, "clear data" and reinstall with the same signing key; it
 * changes after a factory reset, for another user/work profile, or when the signing
 * key changes. No IMEI, MAC address or serial number is used, and no permission is
 * needed. A missing or invalid ANDROID_ID is an error — there is no fallback value.
 *
 * Key: ECDSA P-256 / SHA-256 in AndroidKeyStore, StrongBox when the device has it,
 * otherwise the TEE. The private key is non-exportable. A key that would only be
 * software-backed is deleted and refused (INSECURE_HARDWARE): the app never
 * downgrades silently. The security level is reported to the backend, which applies
 * the enrollment policy (STRONGBOX or TEE). Keystore entries are removed by Android
 * when the app is uninstalled or its data is cleared — the device must then re-bind
 * through OTP.
 */
class DeviceIdentityChannel(private val context: Context) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL = "com.bprdmb.mbanking/device_identity"
        private const val KEYSTORE = "AndroidKeyStore"
        private val ALIAS = Regex("^dmb_device_key_[a-z0-9_]{1,40}$")
        private val HEX_ID = Regex("^[0-9a-f]{1,16}$")

        // Value shared by many devices on an old Android release (never a valid identity).
        private const val KNOWN_SHARED_ANDROID_ID = "9774d56d682e549c"
    }

    private class Failure(val code: String, message: String) : Exception(message)

    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getDeviceIdentity" -> respond(result) { identity() }
            "getKeyInfo" -> respond(result) { keyInfo(alias(call)) }
            "generateKey" -> respond(result) { generateKey(alias(call), attestationChallenge(call)) }
            "sign" -> respond(result) { sign(alias(call), call.argument<String>("message")) }
            "deleteKey" -> respond(result) { deleteKey(alias(call)); true }
            else -> result.notImplemented()
        }
    }

    /** Keystore operations can take hundreds of ms (StrongBox): never on the UI thread. */
    private fun respond(result: MethodChannel.Result, block: () -> Any?) {
        worker.execute {
            try {
                val value = block()
                main.post { result.success(value) }
            } catch (e: Failure) {
                main.post { result.error(e.code, e.message, null) }
            } catch (e: Exception) {
                // Only the exception type: messages may contain device details.
                main.post { result.error("KEYSTORE_ERROR", e.javaClass.simpleName, null) }
            }
        }
    }

    private fun alias(call: MethodCall): String {
        val a = call.argument<String>("alias") ?: ""
        if (!ALIAS.matches(a)) throw Failure("INVALID_ARGUMENT", "Alias kunci tidak valid")
        return a
    }

    // ------------------------------------------------------------------ identity

    private fun identity(): Map<String, Any?> {
        val raw = Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)
        val id = raw?.trim()?.lowercase()
        if (id.isNullOrEmpty() || !HEX_ID.matches(id) || id == KNOWN_SHARED_ANDROID_ID || id.all { it == '0' }) {
            throw Failure("DEVICE_ID_UNAVAILABLE", "Identitas perangkat Android tidak tersedia")
        }
        // Identifiers of the previous app version are not derived any more: a legacy
        // binding is recovered only through OTP (Lupa Password).
        return mapOf("device_id" to "and-" + id.padStart(16, '0'), "platform" to "android")
    }

    // ------------------------------------------------------------------ keys

    private fun keyStore(): KeyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }

    private fun entry(alias: String): KeyStore.PrivateKeyEntry? =
        keyStore().getEntry(alias, null) as? KeyStore.PrivateKeyEntry

    private fun keyInfo(alias: String): Map<String, Any?> {
        val e = entry(alias) ?: return mapOf("exists" to false)
        return mapOf(
            "exists" to true,
            "public_key" to b64(e.certificate.publicKey.encoded), // SubjectPublicKeyInfo DER
            "security_level" to securityLevel(e.privateKey, strongBoxRequested = false),
        )
    }

    /** Server challenge nonce (UTF-8 bytes) embedded in the Key Attestation certificate. */
    private fun attestationChallenge(call: MethodCall): ByteArray {
        val c = call.argument<String>("attestation_challenge") ?: ""
        if (c.isEmpty() || c.length > 128) throw Failure("INVALID_ARGUMENT", "Challenge attestation tidak valid")
        return c.toByteArray(Charsets.UTF_8)
    }

    private fun spec(alias: String, strongBox: Boolean, challenge: ByteArray): KeyGenParameterSpec {
        val b = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN)
            .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
            .setDigests(KeyProperties.DIGEST_SHA256)
            // Used for login/refresh/PIN/password-change proofs; the PIN/password/biometric remain
            // the customer authentication factors (no extra prompt, existing UX kept).
            .setUserAuthenticationRequired(false)
            // Android Key Attestation: the certificate chain proves this key's properties
            // to the server (DB-H6).
            .setAttestationChallenge(challenge)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            // DB-M5: the key can only sign while the device is unlocked.
            b.setUnlockedDeviceRequired(true)
            if (strongBox) b.setIsStrongBoxBacked(true)
        }
        return b.build()
    }

    private fun generateKey(alias: String, challenge: ByteArray): Map<String, Any?> {
        deleteKey(alias) // a fresh key per enrollment: public keys are never reused
        val hasStrongBox = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
            context.packageManager.hasSystemFeature(PackageManager.FEATURE_STRONGBOX_KEYSTORE)
        val generator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, KEYSTORE)
        var usedStrongBox = false
        if (hasStrongBox) {
            try {
                generator.initialize(spec(alias, strongBox = true, challenge = challenge))
                generator.generateKeyPair()
                usedStrongBox = true
            } catch (e: Exception) {
                // StrongBox advertised but unusable (e.g. StrongBoxUnavailableException):
                // the TEE is still hardware-backed and the level is reported as TEE.
                deleteKey(alias)
            }
        }
        if (!usedStrongBox) {
            generator.initialize(spec(alias, strongBox = false, challenge = challenge))
            generator.generateKeyPair()
        }
        val e = entry(alias) ?: throw Failure("KEYSTORE_ERROR", "Kunci tidak tersimpan")
        val level = securityLevel(e.privateKey, usedStrongBox)
        if (level != "STRONGBOX" && level != "TEE") {
            deleteKey(alias)
            throw Failure("INSECURE_HARDWARE", "Perangkat tidak memiliki penyimpanan kunci berbasis hardware")
        }
        // Leaf first; the server verifies the chain against the official Google roots.
        val chain = keyStore().getCertificateChain(alias)?.map { b64(it.encoded) } ?: emptyList()
        if (chain.size < 2) {
            deleteKey(alias)
            throw Failure("ATTESTATION_UNAVAILABLE", "Perangkat tidak menyediakan attestation kunci")
        }
        return mapOf(
            "exists" to true,
            "public_key" to b64(e.certificate.publicKey.encoded),
            // Reported for information only: the server derives the level from the chain.
            "security_level" to level,
            "attestation_chain" to chain,
        )
    }

    private fun securityLevel(key: PrivateKey, strongBoxRequested: Boolean): String {
        val info = KeyFactory.getInstance(key.algorithm, KEYSTORE).getKeySpec(key, KeyInfo::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return when (info.securityLevel) {
                KeyProperties.SECURITY_LEVEL_STRONGBOX -> "STRONGBOX"
                // UNKNOWN_SECURE = secure hardware of an unspecified kind.
                KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT, KeyProperties.SECURITY_LEVEL_UNKNOWN_SECURE -> "TEE"
                else -> "SOFTWARE"
            }
        }
        @Suppress("DEPRECATION")
        val inside = info.isInsideSecureHardware
        return when {
            !inside -> "SOFTWARE"
            strongBoxRequested -> "STRONGBOX"
            else -> "TEE" // API < 31 cannot tell StrongBox apart later: reported conservatively
        }
    }

    private fun sign(alias: String, messageB64: String?): String {
        val msg = try {
            Base64.decode(messageB64 ?: "", Base64.NO_WRAP)
        } catch (e: IllegalArgumentException) {
            throw Failure("INVALID_ARGUMENT", "Pesan tidak valid")
        }
        if (msg.isEmpty()) throw Failure("INVALID_ARGUMENT", "Pesan kosong")
        val e = entry(alias) ?: throw Failure("KEY_NOT_FOUND", "Kunci perangkat tidak ditemukan")
        val s = Signature.getInstance("SHA256withECDSA")
        s.initSign(e.privateKey)
        s.update(msg)
        return b64(s.sign()) // ASN.1 DER (r, s)
    }

    private fun deleteKey(alias: String) {
        val ks = keyStore()
        if (ks.containsAlias(alias)) ks.deleteEntry(alias)
    }

    private fun b64(bytes: ByteArray): String = Base64.encodeToString(bytes, Base64.NO_WRAP)
}
