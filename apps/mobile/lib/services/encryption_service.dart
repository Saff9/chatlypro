// ignore_for_file: non_constant_identifier_names

import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as crypto_hash; // standard hashing for safety numbers
import 'package:hive/hive.dart';

/// Signal Protocol Sender Key record for group E2EE.
/// Each group member generates one SenderKeyRecord and distributes it to peers.
class SenderKeyRecord {
  final String groupId;
  final String senderUsername;
  /// 32-byte HMAC-SHA256 ratcheting chain key (base64).
  String chainKeyBase64;
  /// Ed25519 signing private key (base64).
  String signingPrivateBase64;
  /// Ed25519 signing public key (base64) — sent with every message.
  String signingPublicBase64;
  /// Monotonically increasing message counter.
  int iteration;

  SenderKeyRecord({
    required this.groupId,
    required this.senderUsername,
    required this.chainKeyBase64,
    required this.signingPrivateBase64,
    required this.signingPublicBase64,
    required this.iteration,
  });

  Map<String, dynamic> toJson() => {
        'groupId': groupId,
        'senderUsername': senderUsername,
        'chainKeyBase64': chainKeyBase64,
        'signingPrivateBase64': signingPrivateBase64,
        'signingPublicBase64': signingPublicBase64,
        'iteration': iteration,
      };

  factory SenderKeyRecord.fromJson(Map<String, dynamic> json) =>
      SenderKeyRecord(
        groupId: json['groupId'] as String,
        senderUsername: json['senderUsername'] as String,
        chainKeyBase64: json['chainKeyBase64'] as String,
        signingPrivateBase64: json['signingPrivateBase64'] as String,
        signingPublicBase64: json['signingPublicBase64'] as String,
        iteration: json['iteration'] as int,
      );
}

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

  // ─── Group Key Distribution (ECIES) ────────────────────────────────────────

  /// Wraps a raw 32-byte group key for a specific recipient using ECIES
  /// (ephemeral X25519 + HKDF + AES-256-GCM). The returned base64 packet
  /// can be stored server-side and only the recipient's private key can unwrap it.
  Future<String> wrapGroupKey({
    required List<int> groupKey,
    required String recipientDhPublicBase64,
  }) async {
    // 1. Generate ephemeral X25519 keypair
    final ek = await _x25519.newKeyPair();
    final ekPub = await ek.extractPublicKey();

    // 2. Compute X25519 shared secret
    final recipientPub = SimplePublicKey(
      base64Decode(recipientDhPublicBase64),
      type: KeyPairType.x25519,
    );
    final shared = await _x25519.sharedSecretKey(keyPair: ek, remotePublicKey: recipientPub);
    final sharedBytes = await shared.extractBytes();

    // 3. Derive 32-byte wrapping key via HKDF
    final hkdf = Hkdf(hmac: Hmac(Sha256()), outputLength: 32);
    final wk = await hkdf.deriveKey(
      secretKey: SecretKey(sharedBytes),
      nonce: const [],
      info: utf8.encode('ChatlyGroupKeyWrap'),
    );

    // 4. Encrypt group key with AES-256-GCM
    final secretBox = await _cipher.encrypt(groupKey, secretKey: wk);

    // 5. Return serialized packet
    final packet = {
      'ek_pub': base64Encode(ekPub.bytes),
      'cipher': base64Encode(secretBox.cipherText),
      'nonce': base64Encode(secretBox.nonce),
      'mac': base64Encode(secretBox.mac.bytes),
    };
    return base64Encode(utf8.encode(jsonEncode(packet)));
  }

  /// Unwraps an ECIES-wrapped group key packet using the recipient's DH private key.
  Future<List<int>> unwrapGroupKey({
    required String wrappedKeyBase64,
    required String myDhPrivateBase64,
    required String myDhPublicBase64,
  }) async {
    final decoded = jsonDecode(utf8.decode(base64Decode(wrappedKeyBase64))) as Map<String, dynamic>;

    final ekPubBytes = base64Decode(decoded['ek_pub'] as String);
    final cipherText = base64Decode(decoded['cipher'] as String);
    final nonce = base64Decode(decoded['nonce'] as String);
    final macBytes = base64Decode(decoded['mac'] as String);

    // 1. Reconstruct my DH keypair
    final myPair = SimpleKeyPairData(
      base64Decode(myDhPrivateBase64),
      publicKey: SimplePublicKey(base64Decode(myDhPublicBase64), type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );

    // 2. Compute X25519 shared secret with ephemeral public key
    final ekPub = SimplePublicKey(ekPubBytes, type: KeyPairType.x25519);
    final shared = await _x25519.sharedSecretKey(keyPair: myPair, remotePublicKey: ekPub);
    final sharedBytes = await shared.extractBytes();

    // 3. Derive wrapping key via HKDF
    final hkdf = Hkdf(hmac: Hmac(Sha256()), outputLength: 32);
    final wk = await hkdf.deriveKey(
      secretKey: SecretKey(sharedBytes),
      nonce: const [],
      info: utf8.encode('ChatlyGroupKeyWrap'),
    );

    // 4. Decrypt and return raw group key bytes
    final secretBox = SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes));
    return await _cipher.decrypt(secretBox, secretKey: wk);
  }

  // ─── Group Sender Keys (Signal Protocol — Sender Key Distribution) ──────────
  //
  // Each group member independently generates a SenderKeyRecord containing:
  //   • A 32-byte HMAC-SHA256 ratcheting chain key
  //   • An Ed25519 signing keypair to authenticate every message
  //
  // The SenderKey is serialised, then encrypted individually for each group
  // member using an X25519 ECDH key agreement (see encryptSenderKeyForPeer /
  // decryptSenderKeyFromPeer).  The server stores only opaque ciphertext.
  //
  // To send a group message:
  //   1. Call encryptGroupMessage() — advances chain key, AES-256-GCM + signature.
  //   2. Send the resulting ciphertext over the WebSocket.
  //
  // To receive a group message:
  //   1. Fetch the sender's SenderKey bundle from the server (encrypted for you).
  //   2. Call decryptSenderKeyFromPeer() to reconstruct the SenderKeyRecord.
  //   3. Call decryptGroupMessage() to verify signature + decrypt.

  /// Generates a fresh SenderKeyRecord for the caller in [groupId].
  Future<SenderKeyRecord> generateSenderKey({
    required String groupId,
    required String myUsername,
  }) async {
    // 32-byte random chain key
    final chainKeyPair = await _x25519.newKeyPair();
    final chainKeyBytes = await chainKeyPair.extractPrivateKeyBytes();

    // Ed25519 signing keypair
    final signingPair = await _ed25519.newKeyPair();
    final signingPublicBytes =
        (await signingPair.extractPublicKey()).bytes;
    final signingPrivateBytes =
        await signingPair.extractPrivateKeyBytes();

    return SenderKeyRecord(
      groupId: groupId,
      senderUsername: myUsername,
      chainKeyBase64: base64Encode(chainKeyBytes),
      signingPrivateBase64: base64Encode(signingPrivateBytes),
      signingPublicBase64: base64Encode(signingPublicBytes),
      iteration: 0,
    );
  }

  /// Encrypts [plaintext] using the Sender Key ratchet.
  /// Mutates [senderKey].iteration and [senderKey].chainKeyBase64.
  Future<String> encryptGroupMessage({
    required SenderKeyRecord senderKey,
    required String plaintext,
  }) async {
    // 1. Derive message key from current chain key
    final chainKeyBytes = base64Decode(senderKey.chainKeyBase64);
    final hmac = Hmac(Sha256());
    final msgKeyMac =
        await hmac.calculateMac([0x01], secretKey: SecretKey(chainKeyBytes));
    final nextChainKeyMac =
        await hmac.calculateMac([0x02], secretKey: SecretKey(chainKeyBytes));

    // 2. Advance chain key
    senderKey.chainKeyBase64 = base64Encode(nextChainKeyMac.bytes);
    final currentIteration = senderKey.iteration;
    senderKey.iteration += 1;

    // 3. AES-256-GCM encrypt
    final secretBox = await _cipher.encrypt(
      utf8.encode(plaintext),
      secretKey: SecretKey(msgKeyMac.bytes),
    );

    // 4. Sign the ciphertext with the Ed25519 signing key
    final signingPair = SimpleKeyPairData(
      base64Decode(senderKey.signingPrivateBase64),
      publicKey: SimplePublicKey(
          base64Decode(senderKey.signingPublicBase64),
          type: KeyPairType.ed25519),
      type: KeyPairType.ed25519,
    );
    final signature = await _ed25519.sign(
      secretBox.cipherText + secretBox.nonce + secretBox.mac.bytes,
      keyPair: signingPair,
    );

    final packet = {
      'iteration': currentIteration,
      'signerPub': senderKey.signingPublicBase64,
      'cipher': base64Encode(secretBox.cipherText),
      'nonce': base64Encode(secretBox.nonce),
      'mac': base64Encode(secretBox.mac.bytes),
      'sig': base64Encode(signature.bytes),
    };

    return base64Encode(utf8.encode(jsonEncode(packet)));
  }

  /// Decrypts a group message encrypted with [senderKey].
  /// Advances [senderKey] chain to the packet's iteration.
  Future<String> decryptGroupMessage({
    required SenderKeyRecord senderKey,
    required String encryptedPacketBase64,
  }) async {
    final json = jsonDecode(utf8.decode(base64Decode(encryptedPacketBase64)))
        as Map<String, dynamic>;

    final packetIteration = json['iteration'] as int;
    final signerPubBase64 = json['signerPub'] as String;
    final cipherBytes = base64Decode(json['cipher'] as String);
    final nonceBytes = base64Decode(json['nonce'] as String);
    final macBytes = base64Decode(json['mac'] as String);
    final sigBytes = base64Decode(json['sig'] as String);

    // 1. Verify Ed25519 signature
    if (signerPubBase64 != senderKey.signingPublicBase64) {
      throw Exception(
          '[Group E2EE] Signing key mismatch — possible impersonation.');
    }
    final signerPub = SimplePublicKey(base64Decode(signerPubBase64),
        type: KeyPairType.ed25519);
    final sig = Signature(sigBytes, publicKey: signerPub);
    final valid =
        await _ed25519.verify(cipherBytes + nonceBytes + macBytes, signature: sig);
    if (!valid) {
      throw Exception('[Group E2EE] Signature verification failed.');
    }

    // 2. Advance chain to packetIteration if behind
    final hmac = Hmac(Sha256());
    while (senderKey.iteration <= packetIteration) {
      final chainKeyBytes = base64Decode(senderKey.chainKeyBase64);
      final nextChainKeyMac = await hmac.calculateMac(
          [0x02], secretKey: SecretKey(chainKeyBytes));
      if (senderKey.iteration == packetIteration) {
        // Derive message key at this iteration before advancing
        final msgKeyMac = await hmac.calculateMac(
            [0x01], secretKey: SecretKey(chainKeyBytes));
        senderKey.chainKeyBase64 = base64Encode(nextChainKeyMac.bytes);
        senderKey.iteration += 1;

        final secretBox = SecretBox(cipherBytes,
            nonce: nonceBytes, mac: Mac(macBytes));
        final cleartextBytes = await _cipher.decrypt(
          secretBox,
          secretKey: SecretKey(msgKeyMac.bytes),
        );
        return utf8.decode(cleartextBytes);
      }
      senderKey.chainKeyBase64 = base64Encode(nextChainKeyMac.bytes);
      senderKey.iteration += 1;
    }

    throw Exception(
        '[Group E2EE] Message iteration $packetIteration already consumed '
        '(current: ${senderKey.iteration}).');
  }

  /// Encrypts a [SenderKeyRecord] for distribution to a peer.
  /// Uses ephemeral X25519 DH against the peer's [peerDhIdentityPublicBase64].
  Future<String> encryptSenderKeyForPeer({
    required SenderKeyRecord senderKey,
    required String peerDhIdentityPublicBase64,
  }) async {
    // 1. Ephemeral X25519 keypair
    final ephPair = await _x25519.newKeyPair();
    final ephPub = await ephPair.extractPublicKey();

    // 2. DH shared secret with peer's identity DH key
    final peerPub = SimplePublicKey(
        base64Decode(peerDhIdentityPublicBase64),
        type: KeyPairType.x25519);
    final sharedSecret =
        await _x25519.sharedSecretKey(keyPair: ephPair, remotePublicKey: peerPub);

    // 3. HKDF → 32-byte encryption key
    final hkdf = Hkdf(hmac: Hmac(Sha256()), outputLength: 32);
    final encKey = await hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: utf8.encode('ChatlyGroupSenderKeyDist'),
      info: utf8.encode('sender-key-v1'),
    );

    // 4. AES-256-GCM encrypt the serialised sender key
    final payload = utf8.encode(jsonEncode(senderKey.toJson()));
    final secretBox = await _cipher.encrypt(payload, secretKey: encKey);

    final bundle = {
      'ephPub': base64Encode(ephPub.bytes),
      'cipher': base64Encode(secretBox.cipherText),
      'nonce': base64Encode(secretBox.nonce),
      'mac': base64Encode(secretBox.mac.bytes),
    };
    return base64Encode(utf8.encode(jsonEncode(bundle)));
  }

  /// Decrypts a SenderKey bundle received from the server.
  /// Uses [myDhIdentityPrivateBase64] + [myDhIdentityPublicBase64] to recompute DH.
  Future<SenderKeyRecord> decryptSenderKeyFromPeer({
    required String encryptedBundleBase64,
    required String myDhIdentityPrivateBase64,
    required String myDhIdentityPublicBase64,
  }) async {
    final bundle = jsonDecode(utf8.decode(base64Decode(encryptedBundleBase64)))
        as Map<String, dynamic>;

    final ephPub = SimplePublicKey(
        base64Decode(bundle['ephPub'] as String),
        type: KeyPairType.x25519);

    // Reconstruct my DH identity keypair
    final myPair = SimpleKeyPairData(
      base64Decode(myDhIdentityPrivateBase64),
      publicKey: SimplePublicKey(base64Decode(myDhIdentityPublicBase64),
          type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );

    final sharedSecret =
        await _x25519.sharedSecretKey(keyPair: myPair, remotePublicKey: ephPub);

    final hkdf = Hkdf(hmac: Hmac(Sha256()), outputLength: 32);
    final encKey = await hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: utf8.encode('ChatlyGroupSenderKeyDist'),
      info: utf8.encode('sender-key-v1'),
    );

    final secretBox = SecretBox(
      base64Decode(bundle['cipher'] as String),
      nonce: base64Decode(bundle['nonce'] as String),
      mac: Mac(base64Decode(bundle['mac'] as String)),
    );

    final payload = await _cipher.decrypt(secretBox, secretKey: encKey);
    final recordJson =
        jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
    return SenderKeyRecord.fromJson(recordJson);
  }

  // ─── General-Purpose AES-256-GCM Helpers ─────────────────────────────────

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

class IdentityTrustService {
  static const _prefix = 'trusted_identity_sign_pub_';

  Future<bool> isSafetyVerified(String username) async {
    final box = await Hive.openBox('secure_vault');
    return box.get('safety_verified_$username', defaultValue: false) as bool;
  }

  Future<void> setSafetyVerified(String username, bool verified) async {
    final box = await Hive.openBox('secure_vault');
    await box.put('safety_verified_$username', verified);
  }

  Future<IdentityTrustResult> checkAndPin({
    required String username,
    required String identitySignPublicKey,
  }) async {
    final box = await Hive.openBox('secure_vault');
    final key = '$_prefix$username';
    final existing = box.get(key) as String?;

    if (existing == null || existing.isEmpty) {
      await box.put(key, identitySignPublicKey);
      return IdentityTrustResult.firstUse;
    }

    if (existing == identitySignPublicKey) {
      return IdentityTrustResult.trusted;
    }

    return IdentityTrustResult.changed;
  }

  Future<void> acceptChangedIdentity({
    required String username,
    required String newIdentitySignPublicKey,
  }) async {
    final box = await Hive.openBox('secure_vault');
    await box.put('$_prefix$username', newIdentitySignPublicKey);
  }
}

enum IdentityTrustResult {
  firstUse,
  trusted,
  changed,
}
