// ignore_for_file: non_constant_identifier_names

import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as crypto_hash; // standard hashing for safety numbers

/// Represents a persistent Double Ratchet session state for a contact
class DoubleRatchetSession {
  final String peerUsername;
  String rootKeyBase64;
  String? sendChainKeyBase64;
  String? recvChainKeyBase64;
  String localDhPrivBase64;
  String localDhPubBase64;
  String remoteDhPubBase64;
  int Ns; // Messages sent in current ratchet
  int Nr; // Messages received in current ratchet
  int PN; // Number of messages sent in previous ratchet
  Map<String, String> skippedMessageKeys; // "remoteDhPub_msgNum" -> "messageKeyBase64"

  DoubleRatchetSession({
    required this.peerUsername,
    required this.rootKeyBase64,
    this.sendChainKeyBase64,
    this.recvChainKeyBase64,
    required this.localDhPrivBase64,
    required this.localDhPubBase64,
    required this.remoteDhPubBase64,
    required this.Ns,
    required this.Nr,
    required this.PN,
    required this.skippedMessageKeys,
  });

  Map<String, dynamic> toJson() {
    return {
      'peerUsername': peerUsername,
      'rootKeyBase64': rootKeyBase64,
      'sendChainKeyBase64': sendChainKeyBase64,
      'recvChainKeyBase64': recvChainKeyBase64,
      'localDhPrivBase64': localDhPrivBase64,
      'localDhPubBase64': localDhPubBase64,
      'remoteDhPubBase64': remoteDhPubBase64,
      'Ns': Ns,
      'Nr': Nr,
      'PN': PN,
      'skippedMessageKeys': skippedMessageKeys,
    };
  }

  factory DoubleRatchetSession.fromJson(Map<String, dynamic> json) {
    return DoubleRatchetSession(
      peerUsername: json['peerUsername'] as String,
      rootKeyBase64: json['rootKeyBase64'] as String,
      sendChainKeyBase64: json['sendChainKeyBase64'] as String?,
      recvChainKeyBase64: json['recvChainKeyBase64'] as String?,
      localDhPrivBase64: json['localDhPrivBase64'] as String,
      localDhPubBase64: json['localDhPubBase64'] as String,
      remoteDhPubBase64: json['remoteDhPubBase64'] as String,
      Ns: json['Ns'] as int,
      Nr: json['Nr'] as int,
      PN: json['PN'] as int,
      skippedMessageKeys: Map<String, String>.from(json['skippedMessageKeys'] as Map),
    );
  }
}

class EncryptionService {
  static final EncryptionService _instance = EncryptionService._internal();
  factory EncryptionService() => _instance;
  EncryptionService._internal();

  final _x25519 = X25519();
  final _ed25519 = Ed25519();
  final _cipher = AesGcm.with256bits();

  // ─── Key Bundle Generation & Signing ───────────────────────────────────────

  /// Generates the complete prekey bundle required for Extended Key Exchange (X3DH-Lite)
  Future<Map<String, String>> generateIdentityKeys() async {
    // 1. Generate Ed25519 Identity Signing Keypair (IK_sign)
    final ikSignPair = await _ed25519.newKeyPair();
    final ikSignPublic = await ikSignPair.extractPublicKey();
    final ikSignPrivateBytes = await ikSignPair.extractPrivateKeyBytes();

    // 2. Generate X25519 Identity DH Keypair (IK_dh)
    final ikDhPair = await _x25519.newKeyPair();
    final ikDhPublic = await ikDhPair.extractPublicKey();
    final ikDhPrivateBytes = await ikDhPair.extractPrivateKeyBytes();

    // 3. Generate X25519 Signed Prekey Keypair (SPK)
    final spkPair = await _x25519.newKeyPair();
    final spkPublic = await spkPair.extractPublicKey();
    final spkPrivateBytes = await spkPair.extractPrivateKeyBytes();

    // 4. Sign the public SPK bytes using the private IK_sign key
    final spkPublicBytes = spkPublic.bytes;
    final signature = await _ed25519.sign(
      spkPublicBytes,
      keyPair: ikSignPair,
    );

    return {
      'identity_sign_public_key': base64Encode(ikSignPublic.bytes),
      'identity_sign_private_key': base64Encode(ikSignPrivateBytes),
      'identity_dh_public_key': base64Encode(ikDhPublic.bytes),
      'identity_dh_private_key': base64Encode(ikDhPrivateBytes),
      'signed_prekey_public_key': base64Encode(spkPublicBytes),
      'signed_prekey_private_key': base64Encode(spkPrivateBytes),
      'signed_prekey_signature': base64Encode(signature.bytes),
    };
  }

  /// Verifies a Signed Prekey Bundle's signature
  Future<bool> verifyBundleSignature({
    required String peerIdentitySignPublicBase64,
    required String peerSignedPrekeyPublicBase64,
    required String peerSignatureBase64,
  }) async {
    try {
      final identitySignBytes = base64Decode(peerIdentitySignPublicBase64);
      final signedPrekeyBytes = base64Decode(peerSignedPrekeyPublicBase64);
      final signatureBytes = base64Decode(peerSignatureBase64);

      final publicKey = SimplePublicKey(identitySignBytes, type: KeyPairType.ed25519);
      final signature = Signature(signatureBytes, publicKey: publicKey);

      return await _ed25519.verify(
        signedPrekeyBytes,
        signature: signature,
      );
    } catch (_) {
      return false;
    }
  }

  // ─── Double Ratchet Handshake ──────────────────────────────────────────────

  /// Performs initiator DH handshake (X3DH-Lite) and builds initial DoubleRatchetSession
  Future<DoubleRatchetSession> initInitiatorSession({
    required String peerUsername,
    required String myDhIdentityPrivateBase64,
    required String myDhIdentityPublicBase64,
    required String peerIdentitySignPublicBase64,
    required String peerIdentityDhPublicBase64,
    required String peerSignedPrekeyPublicBase64,
    required String peerSignatureBase64,
  }) async {
    // 1. Verify Signed Prekey
    final isSignatureValid = await verifyBundleSignature(
      peerIdentitySignPublicBase64: peerIdentitySignPublicBase64,
      peerSignedPrekeyPublicBase64: peerSignedPrekeyPublicBase64,
      peerSignatureBase64: peerSignatureBase64,
    );
    if (!isSignatureValid) {
      throw Exception('Prekey bundle verification failed. Untrusted signature.');
    }

    // 2. Generate Ephemeral Keypair (EK_A)
    final ekA = await _x25519.newKeyPair();
    final ekAPublic = await ekA.extractPublicKey();
    final ekAPrivateBytes = await ekA.extractPrivateKeyBytes();

    // Reconstruct my Identity DH Keypair
    final myDhIdentityPair = SimpleKeyPairData(
      base64Decode(myDhIdentityPrivateBase64),
      publicKey: SimplePublicKey(base64Decode(myDhIdentityPublicBase64), type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );

    // Reconstruct Peer Public Keys
    final peerIdentityDhPublic = SimplePublicKey(base64Decode(peerIdentityDhPublicBase64), type: KeyPairType.x25519);
    final peerSignedPrekeyPublic = SimplePublicKey(base64Decode(peerSignedPrekeyPublicBase64), type: KeyPairType.x25519);

    // 3. Perform DH Agreements
    final dh1 = await _x25519.sharedSecretKey(keyPair: myDhIdentityPair, remotePublicKey: peerSignedPrekeyPublic);
    final dh2 = await _x25519.sharedSecretKey(keyPair: ekA, remotePublicKey: peerIdentityDhPublic);
    final dh3 = await _x25519.sharedSecretKey(keyPair: ekA, remotePublicKey: peerSignedPrekeyPublic);

    final dh1Bytes = await dh1.extractBytes();
    final dh2Bytes = await dh2.extractBytes();
    final dh3Bytes = await dh3.extractBytes();

    final allDhBytes = Uint8List.fromList(dh1Bytes + dh2Bytes + dh3Bytes);

    // 4. Derive Root Key and Send Chain Key via HKDF
    final rootKdf = await _kdfRoot(utf8.encode('ChatlyDRRootSalt'), allDhBytes);

    // 5. Initialize the Session State
    return DoubleRatchetSession(
      peerUsername: peerUsername,
      rootKeyBase64: base64Encode(rootKdf['rootKey']!),
      sendChainKeyBase64: base64Encode(rootKdf['chainKey']!),
      recvChainKeyBase64: null,
      localDhPrivBase64: base64Encode(ekAPrivateBytes),
      localDhPubBase64: base64Encode(ekAPublic.bytes),
      remoteDhPubBase64: peerSignedPrekeyPublicBase64,
      Ns: 0,
      Nr: 0,
      PN: 0,
      skippedMessageKeys: {},
    );
  }

  /// Performs receiver DH handshake (X3DH-Lite) and builds initial DoubleRatchetSession
  Future<DoubleRatchetSession> initReceiverSession({
    required String peerUsername,
    required String myDhIdentityPrivateBase64,
    required String myDhIdentityPublicBase64,
    required String mySignedPrekeyPrivateBase64,
    required String mySignedPrekeyPublicBase64,
    required String peerIdentityDhPublicBase64,
    required String peerEphemeralPublicBase64,
  }) async {
    // Reconstruct my Identity DH Keypair
    final myDhIdentityPair = SimpleKeyPairData(
      base64Decode(myDhIdentityPrivateBase64),
      publicKey: SimplePublicKey(base64Decode(myDhIdentityPublicBase64), type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );

    // Reconstruct my Signed Prekey Keypair
    final mySpkPair = SimpleKeyPairData(
      base64Decode(mySignedPrekeyPrivateBase64),
      publicKey: SimplePublicKey(base64Decode(mySignedPrekeyPublicBase64), type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );

    // Reconstruct Peer Public Keys
    final peerIdentityDhPublic = SimplePublicKey(base64Decode(peerIdentityDhPublicBase64), type: KeyPairType.x25519);
    final peerEphemeralPublic = SimplePublicKey(base64Decode(peerEphemeralPublicBase64), type: KeyPairType.x25519);

    // 3. Perform DH Agreements
    final dh1 = await _x25519.sharedSecretKey(keyPair: mySpkPair, remotePublicKey: peerIdentityDhPublic);
    final dh2 = await _x25519.sharedSecretKey(keyPair: myDhIdentityPair, remotePublicKey: peerEphemeralPublic);
    final dh3 = await _x25519.sharedSecretKey(keyPair: mySpkPair, remotePublicKey: peerEphemeralPublic);

    final dh1Bytes = await dh1.extractBytes();
    final dh2Bytes = await dh2.extractBytes();
    final dh3Bytes = await dh3.extractBytes();

    final allDhBytes = Uint8List.fromList(dh1Bytes + dh2Bytes + dh3Bytes);

    // 4. Derive Root Key and Recv Chain Key via HKDF
    final rootKdf = await _kdfRoot(utf8.encode('ChatlyDRRootSalt'), allDhBytes);

    // 5. Initialize the Session State
    return DoubleRatchetSession(
      peerUsername: peerUsername,
      rootKeyBase64: base64Encode(rootKdf['rootKey']!),
      sendChainKeyBase64: null,
      recvChainKeyBase64: base64Encode(rootKdf['chainKey']!),
      localDhPrivBase64: mySignedPrekeyPrivateBase64,
      localDhPubBase64: mySignedPrekeyPublicBase64,
      remoteDhPubBase64: peerEphemeralPublicBase64,
      Ns: 0,
      Nr: 0,
      PN: 0,
      skippedMessageKeys: {},
    );
  }

  // ─── Double Ratchet Encryption & Decryption ────────────────────────────────

  /// Encrypts a message, advancing the sending chain and generating new keys if necessary
  Future<String> encrypt({
    required DoubleRatchetSession session,
    required String plaintext,
  }) async {
    // 1. If we don't have a sending chain key, we need to generate a new local DH key
    // and run a DH step (this happens when Bob responds and advances the ratchet)
    if (session.sendChainKeyBase64 == null) {
      final newDhPair = await _x25519.newKeyPair();
      final newDhPublic = await newDhPair.extractPublicKey();
      final newDhPrivateBytes = await newDhPair.extractPrivateKeyBytes();

      final remoteDhPublic = SimplePublicKey(base64Decode(session.remoteDhPubBase64), type: KeyPairType.x25519);
      final dhShared = await _x25519.sharedSecretKey(keyPair: newDhPair, remotePublicKey: remoteDhPublic);
      final dhSharedBytes = await dhShared.extractBytes();

      final rootKdf = await _kdfRoot(base64Decode(session.rootKeyBase64), dhSharedBytes);

      session.rootKeyBase64 = base64Encode(rootKdf['rootKey']!);
      session.sendChainKeyBase64 = base64Encode(rootKdf['chainKey']!);
      session.localDhPrivBase64 = base64Encode(newDhPrivateBytes);
      session.localDhPubBase64 = base64Encode(newDhPublic.bytes);
      session.PN = session.Ns;
      session.Ns = 0;
    }

    // 2. Advance the sending chain to get a unique message key
    final sendChainKeyBytes = base64Decode(session.sendChainKeyBase64!);
    final chainKdf = await _kdfChain(sendChainKeyBytes);

    session.sendChainKeyBase64 = base64Encode(chainKdf['nextChainKey']!);
    final messageKeyBytes = chainKdf['messageKey']!;

    // 3. Encrypt the plaintext using AES-256-GCM
    final cleartextBytes = utf8.encode(plaintext);
    final secretBox = await _cipher.encrypt(
      cleartextBytes,
      secretKey: SecretKey(messageKeyBytes),
    );

    // 4. Prep E2E Header
    final header = {
      'dh_pub': session.localDhPubBase64,
      'Ns': session.Ns,
      'PN': session.PN,
    };

    // 5. Build Unified Packet
    final packet = {
      'header': base64Encode(utf8.encode(jsonEncode(header))),
      'cipher': base64Encode(secretBox.cipherText),
      'nonce': base64Encode(secretBox.nonce),
      'mac': base64Encode(secretBox.mac.bytes),
    };

    session.Ns += 1;

    return base64Encode(utf8.encode(jsonEncode(packet)));
  }

  /// Decrypts a message, catching up skipped messages and updating ratchet state
  Future<String> decrypt({
    required DoubleRatchetSession session,
    required String encryptedPacketBase64,
  }) async {
    final decodedJson = utf8.decode(base64Decode(encryptedPacketBase64));
    final packet = jsonDecode(decodedJson) as Map<String, dynamic>;

    final headerJson = utf8.decode(base64Decode(packet['header']));
    final header = jsonDecode(headerJson) as Map<String, dynamic>;

    final peerDhPubBase64 = header['dh_pub'] as String;
    final peerNs = header['Ns'] as int;
    final peerPN = header['PN'] as int;

    final cipherText = base64Decode(packet['cipher']);
    final nonce = base64Decode(packet['nonce']);
    final macBytes = base64Decode(packet['mac']);

    final secretBox = SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes));

    // 1. Check if the message key was skipped previously
    final skipKey = '${peerDhPubBase64}_$peerNs';
    if (session.skippedMessageKeys.containsKey(skipKey)) {
      final msgKeyBytes = base64Decode(session.skippedMessageKeys[skipKey]!);
      session.skippedMessageKeys.remove(skipKey);

      final cleartextBytes = await _cipher.decrypt(secretBox, secretKey: SecretKey(msgKeyBytes));
      return utf8.decode(cleartextBytes);
    }

    // 2. If a new DH public key is received, perform the DH Ratchet step
    if (peerDhPubBase64 != session.remoteDhPubBase64) {
      // Catch up skipped keys in current receiving chain up to peerPN
      await _skipMessageKeys(session, peerPN);

      // DH Ratchet step 1: Recv Chain
      final localDhPair = SimpleKeyPairData(
        base64Decode(session.localDhPrivBase64),
        publicKey: SimplePublicKey(base64Decode(session.localDhPubBase64), type: KeyPairType.x25519),
        type: KeyPairType.x25519,
      );
      final newRemoteDhPub = SimplePublicKey(base64Decode(peerDhPubBase64), type: KeyPairType.x25519);

      final dhSharedRecv = await _x25519.sharedSecretKey(keyPair: localDhPair, remotePublicKey: newRemoteDhPub);
      final dhSharedRecvBytes = await dhSharedRecv.extractBytes();

      final rootKdf1 = await _kdfRoot(base64Decode(session.rootKeyBase64), dhSharedRecvBytes);
      session.rootKeyBase64 = base64Encode(rootKdf1['rootKey']!);
      session.recvChainKeyBase64 = base64Encode(rootKdf1['chainKey']!);

      // DH Ratchet step 2: Send Chain (generate new local keypair)
      final newLocalDhPair = await _x25519.newKeyPair();
      final newLocalDhPublic = await newLocalDhPair.extractPublicKey();
      final newLocalDhPrivateBytes = await newLocalDhPair.extractPrivateKeyBytes();

      final dhSharedSend = await _x25519.sharedSecretKey(keyPair: newLocalDhPair, remotePublicKey: newRemoteDhPub);
      final dhSharedSendBytes = await dhSharedSend.extractBytes();

      final rootKdf2 = await _kdfRoot(base64Decode(session.rootKeyBase64), dhSharedSendBytes);
      session.rootKeyBase64 = base64Encode(rootKdf2['rootKey']!);
      session.sendChainKeyBase64 = base64Encode(rootKdf2['chainKey']!);

      // Update DH State
      session.localDhPrivBase64 = base64Encode(newLocalDhPrivateBytes);
      session.localDhPubBase64 = base64Encode(newLocalDhPublic.bytes);
      session.remoteDhPubBase64 = peerDhPubBase64;
      session.PN = session.Ns;
      session.Ns = 0;
      session.Nr = 0;
    }

    // 3. Catch up skipped keys in the current receiving chain up to peerNs
    await _skipMessageKeys(session, peerNs);

    // 4. Advance the receiving chain to get the message key
    final recvChainKeyBytes = base64Decode(session.recvChainKeyBase64!);
    final chainKdf = await _kdfChain(recvChainKeyBytes);

    session.recvChainKeyBase64 = base64Encode(chainKdf['nextChainKey']!);
    final messageKeyBytes = chainKdf['messageKey']!;

    session.Nr += 1;

    // 5. Decrypt
    final cleartextBytes = await _cipher.decrypt(
      secretBox,
      secretKey: SecretKey(messageKeyBytes),
    );

    return utf8.decode(cleartextBytes);
  }

  // ─── Cryptographic Helpers ──────────────────────────────────────────────────

  Future<Map<String, List<int>>> _kdfChain(List<int> chainKeyBytes) async {
    final hmac = Hmac(Sha256());
    // derive unique message key
    final macMsgKey = await hmac.calculateMac([1], secretKey: SecretKey(chainKeyBytes));
    // derive next chain key
    final macNextChainKey = await hmac.calculateMac([2], secretKey: SecretKey(chainKeyBytes));
    return {
      'messageKey': macMsgKey.bytes,
      'nextChainKey': macNextChainKey.bytes,
    };
  }

  Future<Map<String, List<int>>> _kdfRoot(List<int> rootKeyBytes, List<int> dhBytes) async {
    final hkdf = Hkdf(hmac: Hmac(Sha256()), outputLength: 64);
    final derived = await hkdf.deriveKey(
      secretKey: SecretKey(dhBytes),
      nonce: rootKeyBytes, // Use rootKey as HKDF salt
      info: utf8.encode('ChatlyDRRootInfoInfo'),
    );
    final derivedBytes = await derived.extractBytes();
    return {
      'rootKey': derivedBytes.sublist(0, 32),
      'chainKey': derivedBytes.sublist(32, 64),
    };
  }

  Future<void> _skipMessageKeys(DoubleRatchetSession session, int peerIndex) async {
    // If our current Nr is way behind, save the skipped keys
    if (session.Nr + 100 < peerIndex) {
      throw Exception('Too many skipped messages: Desynchronized chain.');
    }
    if (session.recvChainKeyBase64 == null) return;

    while (session.Nr < peerIndex) {
      final recvChainKeyBytes = base64Decode(session.recvChainKeyBase64!);
      final chainKdf = await _kdfChain(recvChainKeyBytes);

      session.recvChainKeyBase64 = base64Encode(chainKdf['nextChainKey']!);
      final messageKeyBytes = chainKdf['messageKey']!;

      final skipKey = '${session.remoteDhPubBase64}_${session.Nr}';
      session.skippedMessageKeys[skipKey] = base64Encode(messageKeyBytes);
      session.Nr += 1;
    }
  }

  // ─── Fingerprint / Safety Numbers ──────────────────────────────────────────

  /// Generates a SHA-256 derived 60-digit fingerprint for out-of-band verification
  String deriveFingerprint(String myIdentitySignPub, String peerIdentitySignPub) {
    // Sort keys alphabetically to ensure commutative fingerprint mapping
    final sortedKeys = [myIdentitySignPub, peerIdentitySignPub]..sort();
    final combined = sortedKeys[0] + sortedKeys[1];
    
    final hash = crypto_hash.sha256.convert(utf8.encode(combined));
    final hashBytes = hash.bytes;

    // Convert hash bytes into a 60-digit numeric string (12 blocks of 5 digits)
    var numString = '';
    for (var i = 0; i < hashBytes.length && numString.length < 60; i += 2) {
      final val = (hashBytes[i] << 8) | hashBytes[i + 1];
      // Format as 5 digit padded string
      numString += val.toString().padLeft(5, '0');
    }

    // Trim to exactly 60 digits
    numString = numString.substring(0, 60);

    // Format into 12 blocks of 5 digits for readability
    final blocks = <String>[];
    for (var i = 0; i < 60; i += 5) {
      blocks.add(numString.substring(i, i + 5));
    }

    return blocks.join(' ');
  }

  // ─── Legacy Cryptographic Helpers (For P2P Offline Mesh only) ───────────────

  /// Generates a new X25519 keypair
  Future<SimpleKeyPair> generateKeyPair() async {
    return await _x25519.newKeyPair();
  }

  /// Exports a public key to base64
  Future<String> exportPublicKey(SimpleKeyPair keyPair) async {
    final publicKey = await keyPair.extractPublicKey();
    return base64Encode(publicKey.bytes);
  }

  /// Exports a private key to base64
  Future<String> exportPrivateKey(SimpleKeyPair keyPair) async {
    final privateKeyBytes = await keyPair.extractPrivateKeyBytes();
    return base64Encode(privateKeyBytes);
  }

  /// Imports an X25519 keypair from base64
  Future<SimpleKeyPair> importKeyPair(String publicBase64, String privateBase64) async {
    final publicBytes = base64Decode(publicBase64);
    final privateBytes = base64Decode(privateBase64);
    
    return SimpleKeyPairData(
      privateBytes,
      publicKey: SimplePublicKey(publicBytes, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
  }

  /// Performs a static DH agreement
  Future<SecretKey> deriveSharedSecret({
    required SimpleKeyPair myKeyPair,
    required String recipientPublicBase64,
  }) async {
    final recipientBytes = base64Decode(recipientPublicBase64);
    final recipientPublicKey = SimplePublicKey(recipientBytes, type: KeyPairType.x25519);

    return await _x25519.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: recipientPublicKey,
    );
  }

  /// Encrypts using AES-256-GCM
  Future<String> encryptMessage({
    required String plaintext,
    required SecretKey secretKey,
  }) async {
    final cleartextBytes = utf8.encode(plaintext);
    final secretBox = await _cipher.encrypt(
      cleartextBytes,
      secretKey: secretKey,
    );

    final packet = {
      'cipher': base64Encode(secretBox.cipherText),
      'nonce': base64Encode(secretBox.nonce),
      'mac': base64Encode(secretBox.mac.bytes),
    };

    return base64Encode(utf8.encode(jsonEncode(packet)));
  }

  /// Decrypts using AES-256-GCM
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

      final cleartextBytes = await _cipher.decrypt(
        secretBox,
        secretKey: secretKey,
      );

      return utf8.decode(cleartextBytes);
    } catch (e) {
      throw Exception('Decryption failed: Integrity check or key mismatch.');
    }
  }
}
