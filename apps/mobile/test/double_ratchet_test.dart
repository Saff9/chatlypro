import 'package:flutter_test/flutter_test.dart';
import 'package:chatly/services/encryption_service.dart';

void main() {
  group('Double Ratchet Protocol & Safety Numbers Tests', () {
    final crypto = EncryptionService();

    test('Full Cryptographic Handshake and Ratchet Cycle', () async {
      // 1. Generate identity bundles for Alice and Bob
      final aliceBundle = await crypto.generateIdentityKeys();
      final bobBundle = await crypto.generateIdentityKeys();

      // Verify that bundle keys and signatures are generated and populated
      expect(aliceBundle['identity_sign_public_key'], isNotEmpty);
      expect(bobBundle['signed_prekey_signature'], isNotEmpty);

      // 2. Verify Bob's prekey bundle signature
      final isSignatureValid = await crypto.verifyBundleSignature(
        peerIdentitySignPublicBase64: bobBundle['identity_sign_public_key']!,
        peerSignedPrekeyPublicBase64: bobBundle['signed_prekey_public_key']!,
        peerSignatureBase64: bobBundle['signed_prekey_signature']!,
      );
      expect(isSignatureValid, isTrue);

      // 3. Initialize Alice's Session (Initiator)
      final aliceSession = await crypto.initInitiatorSession(
        peerUsername: 'bob',
        myDhIdentityPrivateBase64: aliceBundle['identity_dh_private_key']!,
        myDhIdentityPublicBase64: aliceBundle['identity_dh_public_key']!,
        peerIdentitySignPublicBase64: bobBundle['identity_sign_public_key']!,
        peerIdentityDhPublicBase64: bobBundle['identity_dh_public_key']!,
        peerSignedPrekeyPublicBase64: bobBundle['signed_prekey_public_key']!,
        peerSignatureBase64: bobBundle['signed_prekey_signature']!,
      );

      // 4. Initialize Bob's Session (Receiver) using Alice's first ephemeral key
      final bobSession = await crypto.initReceiverSession(
        peerUsername: 'alice',
        myDhIdentityPrivateBase64: bobBundle['identity_dh_private_key']!,
        myDhIdentityPublicBase64: bobBundle['identity_dh_public_key']!,
        mySignedPrekeyPrivateBase64: bobBundle['signed_prekey_private_key']!,
        mySignedPrekeyPublicBase64: bobBundle['signed_prekey_public_key']!,
        peerIdentityDhPublicBase64: aliceBundle['identity_dh_public_key']!,
        peerEphemeralPublicBase64: aliceSession.localDhPubBase64,
      );

      // 5. Test Alice sending messages to Bob (Multiple messages in one direction)
      const plain1 = 'Hello Bob, this is a secure whistleblower message!';
      const plain2 = 'Second message in chain, testing symmetric ratchet.';

      final cipher1 = await crypto.encrypt(session: aliceSession, plaintext: plain1);
      final cipher2 = await crypto.encrypt(session: aliceSession, plaintext: plain2);

      // Decrypt on Bob's end
      final decrypted1 = await crypto.decrypt(session: bobSession, encryptedPacketBase64: cipher1);
      final decrypted2 = await crypto.decrypt(session: bobSession, encryptedPacketBase64: cipher2);

      expect(decrypted1, equals(plain1));
      expect(decrypted2, equals(plain2));

      // 6. Test Bob responding to Alice (Triggers DH ratchet rotation)
      const response1 = 'Got it Alice. Rotating our keys now.';
      final cipherResp1 = await crypto.encrypt(session: bobSession, plaintext: response1);

      // Decrypt on Alice's end
      final decryptedResp1 = await crypto.decrypt(session: aliceSession, encryptedPacketBase64: cipherResp1);
      expect(decryptedResp1, equals(response1));

      // 7. Test skipped / out-of-order decryption
      // Alice sends message 3 and 4. Bob receives 4 first, then 3.
      const plain3 = 'Message 3 (will arrive late)';
      const plain4 = 'Message 4 (arrives immediately)';

      final cipher3 = await crypto.encrypt(session: aliceSession, plaintext: plain3);
      final cipher4 = await crypto.encrypt(session: aliceSession, plaintext: plain4);

      // Bob decrypts Message 4 first
      final decrypted4 = await crypto.decrypt(session: bobSession, encryptedPacketBase64: cipher4);
      expect(decrypted4, equals(plain4));

      // Verify that Message 3's key was skipped and stored
      expect(bobSession.skippedMessageKeys.length, equals(1));

      // Bob decrypts Message 3 late
      final decrypted3 = await crypto.decrypt(session: bobSession, encryptedPacketBase64: cipher3);
      expect(decrypted3, equals(plain3));
      expect(bobSession.skippedMessageKeys.length, equals(0)); // verify key was cleared after use

      // 8. Test Safety Numbers (Fingerprint matches)
      final aliceFingerprint = crypto.deriveFingerprint(
        aliceBundle['identity_sign_public_key']!,
        bobBundle['identity_sign_public_key']!,
      );

      final bobFingerprint = crypto.deriveFingerprint(
        bobBundle['identity_sign_public_key']!,
        aliceBundle['identity_sign_public_key']!,
      );

      expect(aliceFingerprint, equals(bobFingerprint));
      expect(aliceFingerprint.replaceAll(' ', '').length, equals(60));
    });
  });
}
