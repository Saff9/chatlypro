import 'dart:convert';
import 'package:cryptography/cryptography.dart';

class EncryptionService {
  static final EncryptionService _instance = EncryptionService._internal();
  factory EncryptionService() => _instance;
  EncryptionService._internal();

  // Cryptographic algorithms used by Chatly
  final _keyAgreementAlgorithm = X25519();
  final _cipherAlgorithm = AesGcm.with256bits();

  /// Generates a new X25519 Identity Keypair for the user
  Future<SimpleKeyPair> generateKeyPair() async {
    return await _keyAgreementAlgorithm.newKeyPair();
  }

  /// Exports a public key to a Base64 string to upload to the server
  Future<String> exportPublicKey(SimpleKeyPair keyPair) async {
    final publicKey = await keyPair.extractPublicKey();
    return base64Encode(publicKey.bytes);
  }

  /// Exports a private key to a Base64 string for secure local storage
  Future<String> exportPrivateKey(SimpleKeyPair keyPair) async {
    final privateKeyBytes = await keyPair.extractPrivateKeyBytes();
    return base64Encode(privateKeyBytes);
  }

  /// Recreates a SimpleKeyPair from stored Base64 public and private key strings
  Future<SimpleKeyPair> importKeyPair(String publicBase64, String privateBase64) async {
    final publicBytes = base64Decode(publicBase64);
    final privateBytes = base64Decode(privateBase64);
    
    return SimpleKeyPairData(
      privateBytes,
      publicKey: SimplePublicKey(publicBytes, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
  }

  /// Performs a Diffie-Hellman Key Agreement to compute a shared session key
  Future<SecretKey> deriveSharedSecret({
    required SimpleKeyPair myKeyPair,
    required String recipientPublicBase64,
  }) async {
    final recipientBytes = base64Decode(recipientPublicBase64);
    final recipientPublicKey = SimplePublicKey(recipientBytes, type: KeyPairType.x25519);

    // Compute the shared secret using X25519 key agreement
    return await _keyAgreementAlgorithm.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: recipientPublicKey,
    );
  }

  /// Encrypts plaintext string using AES-256-GCM with a derived shared secret key
  Future<String> encryptMessage({
    required String plaintext,
    required SecretKey secretKey,
  }) async {
    final cleartextBytes = utf8.encode(plaintext);
    
    // Encrypt using the derived secret key
    final secretBox = await _cipherAlgorithm.encrypt(
      cleartextBytes,
      secretKey: secretKey,
    );

    // Combine cipher, nonce (IV), and mac tag into a unified packet format
    final packet = {
      'cipher': base64Encode(secretBox.cipherText),
      'nonce': base64Encode(secretBox.nonce),
      'mac': base64Encode(secretBox.mac.bytes),
    };

    return base64Encode(utf8.encode(jsonEncode(packet)));
  }

  /// Decrypts ciphertext using AES-256-GCM with the derived shared secret key
  Future<String> decryptMessage({
    required String encryptedPacketBase64,
    required SecretKey secretKey,
  }) async {
    try {
      final decodedJson = utf8.decode(base64Decode(encryptedPacketBase64));
      final packet = jsonDecode(decodedJson) as Map<String, dynamic>;

      final cipherText = base64Decode(packet['cipher']);
      final nonce = base64Decode(packet['nonce']);
      final macBytes = base64Decode(packet['mac']);

      final secretBox = SecretBox(
        cipherText,
        nonce: nonce,
        mac: Mac(macBytes),
      );

      final cleartextBytes = await _cipherAlgorithm.decrypt(
        secretBox,
        secretKey: secretKey,
      );

      return utf8.decode(cleartextBytes);
    } catch (e) {
      throw Exception('Decryption failed: Integrity check or key mismatch.');
    }
  }
}
