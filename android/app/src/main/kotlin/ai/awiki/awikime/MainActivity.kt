package ai.awiki.awikime

import android.app.Activity
import android.content.Intent
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.bouncycastle.asn1.DERBitString
import org.bouncycastle.asn1.ASN1InputStream
import org.bouncycastle.asn1.ASN1Integer
import org.bouncycastle.asn1.ASN1Primitive
import org.bouncycastle.asn1.ASN1Sequence
import org.bouncycastle.asn1.pkcs.PrivateKeyInfo
import org.bouncycastle.asn1.sec.ECPrivateKey as Asn1EcPrivateKey
import org.bouncycastle.asn1.sec.SECObjectIdentifiers
import org.bouncycastle.asn1.x509.AlgorithmIdentifier
import org.bouncycastle.asn1.x509.SubjectPublicKeyInfo
import org.bouncycastle.asn1.x9.X962Parameters
import org.bouncycastle.asn1.x9.X9ObjectIdentifiers
import org.bouncycastle.crypto.AsymmetricCipherKeyPair
import org.bouncycastle.crypto.digests.SHA256Digest
import org.bouncycastle.crypto.ec.CustomNamedCurves
import org.bouncycastle.crypto.generators.ECKeyPairGenerator
import org.bouncycastle.crypto.params.ECDomainParameters
import org.bouncycastle.crypto.params.ECKeyGenerationParameters
import org.bouncycastle.crypto.params.ECPrivateKeyParameters
import org.bouncycastle.crypto.params.ECPublicKeyParameters
import org.bouncycastle.jce.provider.BouncyCastleProvider
import org.bouncycastle.crypto.signers.ECDSASigner
import org.bouncycastle.crypto.signers.HMacDSAKCalculator
import java.math.BigInteger
import java.nio.charset.StandardCharsets
import java.security.KeyPair
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.Security
import java.security.interfaces.ECPrivateKey
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private val logTag = "AWikiMeDid"

    private data class Secp256k1KeyMaterial(
        val privateScalar: BigInteger,
        val publicX: BigInteger,
        val publicY: BigInteger,
        val privateKeyDer: ByteArray,
        val publicKeyDer: ByteArray,
    )

    companion object {
        private const val DID_CHANNEL = "ai.awiki.awikime/did_registration"
        private const val DOCUMENT_CHANNEL = "ai.awiki.awikime/document_picker"
        private const val REQUEST_SAVE_ZIP = 2001
        private const val REQUEST_PICK_ZIP = 2002
        private const val VM_KEY_AUTH = "key-1"
        private const val VM_KEY_E2EE_SIGNING = "key-2"
        private const val VM_KEY_E2EE_AGREEMENT = "key-3"
        private const val DEFAULT_DOMAIN = "awiki.ai"

        private val CREATED_FORMATTER: DateTimeFormatter =
            DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss'Z'").withZone(ZoneOffset.UTC)
    }

    private var pendingSaveBytes: ByteArray? = null
    private var pendingSaveResult: MethodChannel.Result? = null
    private var pendingPickResult: MethodChannel.Result? = null

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            REQUEST_SAVE_ZIP -> handleSaveResult(resultCode = resultCode, data = data)
            REQUEST_PICK_ZIP -> handlePickResult(resultCode = resultCode, data = data)
        }
    }

    private fun handleSaveResult(resultCode: Int, data: Intent?) {
        val callback = pendingSaveResult
        val bytes = pendingSaveBytes
        pendingSaveBytes = null
        pendingSaveResult = null
        if (callback == null) {
            return
        }
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            callback.success(null)
            return
        }
        val uri = data.data ?: return
        if (bytes == null) {
            callback.error("save_failed", "导出内容为空。", null)
            return
        }
        try {
            contentResolver.openOutputStream(uri)?.use { stream ->
                stream.write(bytes)
                stream.flush()
            } ?: throw IllegalStateException("无法打开目标文件。")
            callback.success(uri.toString())
        } catch (e: Exception) {
            callback.error("save_failed", formatExceptionMessage(e), null)
        }
    }

    private fun handlePickResult(resultCode: Int, data: Intent?) {
        val callback = pendingPickResult
        pendingPickResult = null
        if (callback == null) {
            return
        }
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            callback.success(null)
            return
        }
        val uri = data.data ?: return
        try {
            val bytes = contentResolver.openInputStream(uri)?.use { input ->
                input.readBytes()
            } ?: throw IllegalStateException("无法读取所选文件。")
            callback.success(bytes)
        } catch (e: Exception) {
            callback.error("pick_failed", formatExceptionMessage(e), null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        ensureBouncyCastle()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DID_CHANNEL)
            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                when (call.method) {
                    "isSupported" -> result.success(true)
                    "buildRegisterHandleParams" -> {
                        try {
                            val args = call.arguments as? Map<*, *> ?: emptyMap<Any?, Any?>()
                            result.success(buildRegisterHandlePayload(args))
                        } catch (e: Exception) {
                            Log.e(logTag, "Failed to build DID registration payload.", e)
                            result.error("did_build_failed", formatExceptionMessage(e), null)
                        }
                    }
                    "generateDidAuthHeader" -> {
                        try {
                            val args = call.arguments as? Map<*, *> ?: emptyMap<Any?, Any?>()
                            val didDocument = (args["did_document"] as? Map<*, *>)
                                ?: throw IllegalArgumentException("did_document is required")
                            val privateKeyPem = (args["private_key_pem"] as? String)
                                ?.takeIf { it.isNotBlank() }
                                ?: throw IllegalArgumentException("private_key_pem is required")
                            val domain = (args["domain"] as? String)
                                ?.takeIf { it.isNotBlank() }
                                ?: throw IllegalArgumentException("domain is required")
                            result.success(
                                generateDidAuthHeader(
                                    didDocument = didDocument,
                                    privateKeyPem = privateKeyPem,
                                    serviceDomain = domain,
                                )
                            )
                        } catch (e: Exception) {
                            Log.e(logTag, "Failed to generate DID auth header.", e)
                            result.error("did_auth_header_failed", formatExceptionMessage(e), null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DOCUMENT_CHANNEL)
            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                when (call.method) {
                    "saveZipFile" -> {
                        try {
                            val args = call.arguments as? Map<*, *> ?: emptyMap<Any?, Any?>()
                            val fileName = (args["file_name"] as? String)
                                ?.takeIf { it.isNotBlank() }
                                ?: throw IllegalArgumentException("file_name is required")
                            val bytes = when (val raw = args["bytes"]) {
                                is ByteArray -> raw
                                is List<*> -> raw.filterIsInstance<Number>().map { it.toByte() }.toByteArray()
                                else -> throw IllegalArgumentException("bytes is required")
                            }
                            launchSaveDocument(fileName = fileName, bytes = bytes, result = result)
                        } catch (e: Exception) {
                            result.error("save_failed", formatExceptionMessage(e), null)
                        }
                    }
                    "pickZipFile" -> launchPickDocument(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun launchSaveDocument(
        fileName: String,
        bytes: ByteArray,
        result: MethodChannel.Result,
    ) {
        if (pendingSaveResult != null) {
            result.error("save_in_progress", "已有导出任务正在进行。", null)
            return
        }
        pendingSaveResult = result
        pendingSaveBytes = bytes
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/zip"
            putExtra(Intent.EXTRA_TITLE, fileName)
        }
        startActivityForResult(intent, REQUEST_SAVE_ZIP)
    }

    private fun launchPickDocument(result: MethodChannel.Result) {
        if (pendingPickResult != null) {
            result.error("pick_in_progress", "已有导入任务正在进行。", null)
            return
        }
        pendingPickResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/zip"
        }
        startActivityForResult(intent, REQUEST_PICK_ZIP)
    }

    private fun generateDidAuthHeader(
        didDocument: Map<*, *>,
        privateKeyPem: String,
        serviceDomain: String,
        version: String = "1.1",
    ): String {
        val did = didDocument["id"]?.toString()?.takeIf { it.isNotBlank() }
            ?: throw IllegalArgumentException("DID document is missing the id field.")
        val verificationMethodFragment = selectAuthenticationMethodFragment(didDocument)
        val nonce = generateChallengeHex(16)
        val timestamp = CREATED_FORMATTER.format(Instant.now())
        val domainField = "aud"
        val dataToSign = linkedMapOf<String, Any?>(
            "nonce" to nonce,
            "timestamp" to timestamp,
            domainField to serviceDomain,
            "did" to did,
        )
        val canonicalJson = jcsCanonicalize(dataToSign)
        val contentHash = sha256(canonicalJson)
        val privateScalar = loadSecp256k1PrivateScalar(privateKeyPem)
        val signature = signSecp256k1ToRawBase64Url(privateScalar, contentHash)
        return "DIDWba v=\"$version\", did=\"$did\", nonce=\"$nonce\", timestamp=\"$timestamp\", verification_method=\"$verificationMethodFragment\", signature=\"$signature\""
    }

    private fun selectAuthenticationMethodFragment(didDocument: Map<*, *>): String {
        val authentication = didDocument["authentication"] as? List<*>
            ?: throw IllegalArgumentException("DID document is missing authentication methods.")
        if (authentication.isEmpty()) {
            throw IllegalArgumentException("DID document authentication methods are empty.")
        }
        val authMethod = authentication.first()
        val authId = when (authMethod) {
            is String -> authMethod
            is Map<*, *> -> authMethod["id"]?.toString()
            else -> null
        } ?: throw IllegalArgumentException("Invalid authentication method in DID document.")
        return authId.substringAfter('#')
    }

    private fun loadSecp256k1PrivateScalar(privateKeyPem: String): BigInteger {
        val der = decodePem(privateKeyPem)
        val privateKeyInfo = PrivateKeyInfo.getInstance(ASN1Primitive.fromByteArray(der))
        val ecPrivateKey = Asn1EcPrivateKey.getInstance(privateKeyInfo.parsePrivateKey())
        return ecPrivateKey.key
    }

    private fun decodePem(pem: String): ByteArray {
        val base64 = pem
            .lineSequence()
            .filterNot { it.startsWith("-----BEGIN") || it.startsWith("-----END") }
            .joinToString(separator = "")
            .trim()
        if (base64.isEmpty()) {
            throw IllegalArgumentException("PEM content is empty")
        }
        return android.util.Base64.decode(base64, android.util.Base64.DEFAULT)
    }

    private fun buildRegisterHandlePayload(args: Map<*, *>): Map<String, Any?> {
        val handle = (args["handle"] as? String)?.trim()?.takeIf { it.isNotEmpty() } ?: "awikime"
        val domain = ((args["domain"] as? String)?.trim()?.takeIf { it.isNotEmpty() } ?: DEFAULT_DOMAIN)
        val challenge = generateChallengeHex(16)
        val created = CREATED_FORMATTER.format(Instant.now())

        val key1 = generateSecp256k1KeyMaterial()
        val key1Jwk = secp256k1PublicKeyToJwk(
            x = key1.publicX,
            y = key1.publicY,
        )
        val keyFingerprint = computeSecp256k1JwkFingerprint(key1Jwk)

        // Server format: did:wba:{domain}:{handle}:{key_id}
        // Path segment must match registration handle.
        val did = "did:wba:$domain:$handle:k1_$keyFingerprint"
        val key1Id = "$did#$VM_KEY_AUTH"

        val verificationMethods = mutableListOf<Map<String, Any?>>(
            linkedMapOf(
                "id" to key1Id,
                "type" to "EcdsaSecp256k1VerificationKey2019",
                "controller" to did,
                "publicKeyJwk" to key1Jwk,
            ),
        )

        val didDoc = linkedMapOf<String, Any?>(
            "@context" to mutableListOf(
                "https://www.w3.org/ns/did/v1",
                "https://w3id.org/security/suites/jws-2020/v1",
                "https://w3id.org/security/suites/secp256k1-2019/v1",
            ),
            "id" to did,
            "verificationMethod" to verificationMethods,
            "authentication" to listOf(key1Id),
        )

        var key2PemPrivate: String? = null
        var key2PemPublic: String? = null
        try {
            val key2 = generateSecp256r1KeyPair()
            val key2Public = key2.public as ECPublicKey
            verificationMethods.add(
                linkedMapOf(
                    "id" to "$did#$VM_KEY_E2EE_SIGNING",
                    "type" to "EcdsaSecp256r1VerificationKey2019",
                    "controller" to did,
                    "publicKeyJwk" to ecPublicKeyToJwk(key2Public, "P-256"),
                ),
            )
            key2PemPrivate = toPem("PRIVATE KEY", key2.private.encoded)
            key2PemPublic = toPem("PUBLIC KEY", key2.public.encoded)
        } catch (_: Exception) {
            // key-2 为可选扩展，生成失败时不阻断注册。
        }

        var key3PemPrivate: String? = null
        var key3PemPublic: String? = null
        try {
            val key3 = generateX25519KeyPair()
            val rawX25519Public = extractX25519RawPublicKey(key3.public.encoded)
            verificationMethods.add(
                linkedMapOf(
                    "id" to "$did#$VM_KEY_E2EE_AGREEMENT",
                    "type" to "X25519KeyAgreementKey2019",
                    "controller" to did,
                    "publicKeyMultibase" to ("z" + base58Encode(rawX25519Public)),
                ),
            )
            didDoc["keyAgreement"] = listOf("$did#$VM_KEY_E2EE_AGREEMENT")
            (didDoc["@context"] as MutableList<String>).add("https://w3id.org/security/suites/x25519-2019/v1")
            key3PemPrivate = toPem("PRIVATE KEY", key3.private.encoded)
            key3PemPublic = toPem("PUBLIC KEY", key3.public.encoded)
        } catch (_: Exception) {
            // key-3 为可选扩展，生成失败时不阻断注册。
        }

        val proofOptions = linkedMapOf<String, Any?>(
            "type" to "EcdsaSecp256k1Signature2019",
            "created" to created,
            "verificationMethod" to key1Id,
            "proofPurpose" to "authentication",
            "domain" to domain,
            "challenge" to challenge,
        )

        val toBeSigned = buildProofSigningInput(didDoc, proofOptions)
        val proofValue = signSecp256k1ToRawBase64Url(key1.privateScalar, toBeSigned)
        didDoc["proof"] = linkedMapOf<String, Any?>(
            "type" to "EcdsaSecp256k1Signature2019",
            "created" to created,
            "verificationMethod" to key1Id,
            "proofPurpose" to "authentication",
            "domain" to domain,
            "challenge" to challenge,
            "proofValue" to proofValue,
        )

        return linkedMapOf(
            "did" to did,
            "did_document" to didDoc,
            "proof_purpose" to "authentication",
            "domain" to domain,
            "challenge" to challenge,
            "private_key_pem" to toPem("PRIVATE KEY", key1.privateKeyDer),
            "public_key_pem" to toPem("PUBLIC KEY", key1.publicKeyDer),
            "e2ee_signing_private_pem" to key2PemPrivate,
            "e2ee_signing_public_pem" to key2PemPublic,
            "e2ee_agreement_private_pem" to key3PemPrivate,
            "e2ee_agreement_public_pem" to key3PemPublic,
        )
    }

    private fun ensureBouncyCastle() {
        Security.removeProvider(BouncyCastleProvider.PROVIDER_NAME)
        Security.insertProviderAt(BouncyCastleProvider(), 1)
    }

    private fun generateChallengeHex(size: Int): String {
        val bytes = ByteArray(size)
        SecureRandom().nextBytes(bytes)
        return bytes.joinToString(separator = "") { "%02x".format(it) }
    }

    private fun generateSecp256k1KeyMaterial(): Secp256k1KeyMaterial {
        try {
            val bcKeyPair = generateBcSecp256k1KeyPair()
            val publicParams = bcKeyPair.public as ECPublicKeyParameters
            val privateParams = bcKeyPair.private as ECPrivateKeyParameters
            return Secp256k1KeyMaterial(
                privateScalar = privateParams.d,
                publicX = publicParams.q.affineXCoord.toBigInteger(),
                publicY = publicParams.q.affineYCoord.toBigInteger(),
                privateKeyDer = encodeSecp256k1PrivateKeyDer(privateParams, publicParams),
                publicKeyDer = encodeSecp256k1PublicKeyDer(publicParams),
            )
        } catch (e: Exception) {
            throw IllegalStateException(
                "Unable to generate secp256k1 key pair on this Android device.",
                e,
            )
        }
    }

    private fun generateSecp256r1KeyPair(): KeyPair {
        val kpg = java.security.KeyPairGenerator.getInstance("EC")
        kpg.initialize(ECGenParameterSpec("secp256r1"), SecureRandom())
        return kpg.generateKeyPair()
    }

    private fun generateX25519KeyPair(): KeyPair {
        val kpg = java.security.KeyPairGenerator.getInstance("X25519")
        kpg.initialize(255, SecureRandom())
        return kpg.generateKeyPair()
    }

    private fun ecPublicKeyToJwk(publicKey: ECPublicKey, curve: String): Map<String, String> {
        val x = toUnsignedFixed(publicKey.w.affineX, 32)
        val y = toUnsignedFixed(publicKey.w.affineY, 32)
        val compressed = compressEcPoint(x, y)
        val kid = base64UrlNoPadding(sha256(compressed))
        return linkedMapOf(
            "kty" to "EC",
            "crv" to curve,
            "x" to base64UrlNoPadding(x),
            "y" to base64UrlNoPadding(y),
            "kid" to kid,
        )
    }

    private fun secp256k1PublicKeyToJwk(
        x: BigInteger,
        y: BigInteger,
    ): Map<String, String> {
        val xBytes = toUnsignedFixed(x, 32)
        val yBytes = toUnsignedFixed(y, 32)
        val compressed = compressEcPoint(xBytes, yBytes)
        val kid = base64UrlNoPadding(sha256(compressed))
        return linkedMapOf(
            "kty" to "EC",
            "crv" to "secp256k1",
            "x" to base64UrlNoPadding(xBytes),
            "y" to base64UrlNoPadding(yBytes),
            "kid" to kid,
        )
    }

    private fun computeSecp256k1JwkFingerprint(jwk: Map<String, String>): String {
        val canonical = "{\"crv\":\"secp256k1\",\"kty\":\"EC\",\"x\":\"${jwk["x"]}\",\"y\":\"${jwk["y"]}\"}"
        return base64UrlNoPadding(sha256(canonical.toByteArray(StandardCharsets.US_ASCII)))
    }

    private fun buildProofSigningInput(
        documentWithoutProof: Map<String, Any?>,
        proofOptions: Map<String, Any?>,
    ): ByteArray {
        val docHash = sha256(jcsCanonicalize(documentWithoutProof))
        val optionsHash = sha256(jcsCanonicalize(proofOptions))
        val output = ByteArray(optionsHash.size + docHash.size)
        System.arraycopy(optionsHash, 0, output, 0, optionsHash.size)
        System.arraycopy(docHash, 0, output, optionsHash.size, docHash.size)
        return output
    }

    private fun signSecp256k1ToRawBase64Url(privateScalar: BigInteger, data: ByteArray): String {
        val curveParams = requireSecp256k1Curve()
        val domain = ECDomainParameters(
            curveParams.curve,
            curveParams.g,
            curveParams.n,
            curveParams.h,
            curveParams.seed,
        )
        val signer = ECDSASigner(HMacDSAKCalculator(SHA256Digest()))
        signer.init(true, ECPrivateKeyParameters(privateScalar, domain))
        val hashed = sha256(data)
        val signature = signer.generateSignature(hashed)
        val raw = ByteArray(64)
        val rBytes = toUnsignedFixed(signature[0], 32)
        val sBytes = toUnsignedFixed(signature[1], 32)
        System.arraycopy(rBytes, 0, raw, 0, 32)
        System.arraycopy(sBytes, 0, raw, 32, 32)
        return base64UrlNoPadding(raw)
    }

    private fun derEcdsaToRaw(der: ByteArray, fieldSize: Int): ByteArray {
        ASN1InputStream(der).use { input ->
            val seq = input.readObject() as ASN1Sequence
            val r = (seq.getObjectAt(0) as ASN1Integer).value
            val s = (seq.getObjectAt(1) as ASN1Integer).value
            val out = ByteArray(fieldSize * 2)
            val rBytes = toUnsignedFixed(r, fieldSize)
            val sBytes = toUnsignedFixed(s, fieldSize)
            System.arraycopy(rBytes, 0, out, 0, fieldSize)
            System.arraycopy(sBytes, 0, out, fieldSize, fieldSize)
            return out
        }
    }

    private fun jcsCanonicalize(value: Any?): ByteArray {
        val text = jcsSerialize(value)
        return text.toByteArray(StandardCharsets.UTF_8)
    }

    private fun jcsSerialize(value: Any?): String {
        return when (value) {
            null -> "null"
            is String -> jcsQuote(value)
            is Boolean -> if (value) "true" else "false"
            is Int, is Long, is Short, is Byte -> value.toString()
            is BigInteger -> value.toString()
            is Float, is Double -> formatNumber(value as Number)
            is Number -> value.toString()
            is Map<*, *> -> {
                val entries = value.entries
                    .map { (k, v) -> (k?.toString() ?: "") to v }
                    .sortedBy { it.first }
                entries.joinToString(separator = ",", prefix = "{", postfix = "}") { (k, v) ->
                    "${jcsQuote(k)}:${jcsSerialize(v)}"
                }
            }
            is List<*> -> value.joinToString(separator = ",", prefix = "[", postfix = "]") { item -> jcsSerialize(item) }
            is Array<*> -> value.joinToString(separator = ",", prefix = "[", postfix = "]") { item -> jcsSerialize(item) }
            else -> jcsQuote(value.toString())
        }
    }

    private fun jcsQuote(value: String): String {
        val sb = java.lang.StringBuilder()
        sb.append('"')
        for (c in value) {
            when (c) {
                '"' -> sb.append("\\\"")
                '\\' -> sb.append("\\\\")
                '\b' -> sb.append("\\b")
                '\u000C' -> sb.append("\\f")
                '\n' -> sb.append("\\n")
                '\r' -> sb.append("\\r")
                '\t' -> sb.append("\\t")
                else -> {
                    if (c < ' ') {
                        sb.append(String.format("\\u%04x", c.code))
                    } else {
                        sb.append(c)
                    }
                }
            }
        }
        sb.append('"')
        return sb.toString()
    }

    private fun formatNumber(number: Number): String {
        val d = number.toDouble()
        if (!d.isFinite()) {
            throw IllegalArgumentException("JCS does not allow non-finite numbers")
        }
        return java.math.BigDecimal.valueOf(d).stripTrailingZeros().toPlainString()
    }

    private fun formatExceptionMessage(error: Throwable): String {
        val parts = mutableListOf<String>()
        var current: Throwable? = error
        while (current != null && parts.size < 5) {
            val message = current.message?.trim().takeUnless { it.isNullOrEmpty() }
                ?: current::class.java.simpleName
            if (parts.lastOrNull() != message) {
                parts.add(message)
            }
            current = current.cause
        }
        return parts.joinToString(" <- ")
    }

    private fun extractX25519RawPublicKey(spki: ByteArray): ByteArray {
        if (spki.size < 32) {
            throw IllegalArgumentException("Invalid X25519 SPKI length: ${spki.size}")
        }
        return spki.copyOfRange(spki.size - 32, spki.size)
    }

    private fun compressEcPoint(x: ByteArray, y: ByteArray): ByteArray {
        val prefix = if ((y.last().toInt() and 1) == 0) 0x02.toByte() else 0x03.toByte()
        val out = ByteArray(1 + x.size)
        out[0] = prefix
        System.arraycopy(x, 0, out, 1, x.size)
        return out
    }

    private fun toUnsignedFixed(value: BigInteger, size: Int): ByteArray {
        val bytes = value.toByteArray()
        if (bytes.size == size) {
            return bytes
        }
        if (bytes.size == size + 1 && bytes[0] == 0.toByte()) {
            return bytes.copyOfRange(1, bytes.size)
        }
        val out = ByteArray(size)
        val srcPos = maxOf(0, bytes.size - size)
        val copyLength = minOf(bytes.size, size)
        System.arraycopy(bytes, srcPos, out, size - copyLength, copyLength)
        return out
    }

    private fun sha256(input: ByteArray): ByteArray {
        return MessageDigest.getInstance("SHA-256").digest(input)
    }

    private fun generateBcSecp256k1KeyPair(): AsymmetricCipherKeyPair {
        val curveParams = requireSecp256k1Curve()
        val domain = ECDomainParameters(
            curveParams.curve,
            curveParams.g,
            curveParams.n,
            curveParams.h,
            curveParams.seed,
        )
        val generator = ECKeyPairGenerator()
        generator.init(ECKeyGenerationParameters(domain, SecureRandom()))
        return generator.generateKeyPair()
    }

    private fun encodeSecp256k1PublicKeyDer(publicParams: ECPublicKeyParameters): ByteArray {
        val algorithmIdentifier = AlgorithmIdentifier(
            X9ObjectIdentifiers.id_ecPublicKey,
            X962Parameters(SECObjectIdentifiers.secp256k1),
        )
        val publicKeyInfo = SubjectPublicKeyInfo(algorithmIdentifier, publicParams.q.getEncoded(false))
        return publicKeyInfo.encoded
    }

    private fun encodeSecp256k1PrivateKeyDer(
        privateParams: ECPrivateKeyParameters,
        publicParams: ECPublicKeyParameters,
    ): ByteArray {
        val parameters = X962Parameters(SECObjectIdentifiers.secp256k1)
        val privateKey = Asn1EcPrivateKey(
            256,
            privateParams.d,
            DERBitString(publicParams.q.getEncoded(false)),
            parameters,
        )
        val algorithmIdentifier = AlgorithmIdentifier(
            X9ObjectIdentifiers.id_ecPublicKey,
            parameters,
        )
        val privateKeyInfo = PrivateKeyInfo(algorithmIdentifier, privateKey)
        return privateKeyInfo.encoded
    }

    private fun requireSecp256k1Curve() =
        CustomNamedCurves.getByName("secp256k1")
            ?: throw IllegalStateException("BouncyCastle does not expose secp256k1 parameters.")

    private fun base64UrlNoPadding(bytes: ByteArray): String {
        return android.util.Base64.encodeToString(
            bytes,
            android.util.Base64.NO_WRAP or android.util.Base64.NO_PADDING or android.util.Base64.URL_SAFE,
        )
    }

    private fun toPem(label: String, der: ByteArray): String {
        val base64 = android.util.Base64.encodeToString(der, android.util.Base64.NO_WRAP)
        val wrapped = base64.chunked(64).joinToString("\n")
        return "-----BEGIN $label-----\n$wrapped\n-----END $label-----\n"
    }

    private fun base58Encode(input: ByteArray): String {
        if (input.isEmpty()) {
            return ""
        }
        val alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
        var zeros = 0
        while (zeros < input.size && input[zeros].toInt() == 0) {
            zeros++
        }
        val encoded = StringBuilder()
        val copy = input.copyOf()
        var start = zeros
        while (start < copy.size) {
            var remainder = 0
            for (i in start until copy.size) {
                val value = (copy[i].toInt() and 0xFF)
                val temp = remainder * 256 + value
                copy[i] = (temp / 58).toByte()
                remainder = temp % 58
            }
            encoded.append(alphabet[remainder])
            while (start < copy.size && copy[start].toInt() == 0) {
                start++
            }
        }
        repeat(zeros) {
            encoded.append(alphabet[0])
        }
        return encoded.reverse().toString()
    }
}
