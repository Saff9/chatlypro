import { initializeApp, cert } from 'firebase-admin/app';
import { getMessaging, Message } from 'firebase-admin/messaging';
import dotenv from 'dotenv';
import fs from 'fs';

dotenv.config();

let isFirebaseInitialized = false;

const serviceAccountPath = process.env.FIREBASE_SERVICE_ACCOUNT_PATH || './firebase-service-account.json';

try {
  if (fs.existsSync(serviceAccountPath)) {
    console.log(`Initializing Firebase Admin using credentials from ${serviceAccountPath}...`);
    const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, 'utf8'));
    initializeApp({
      credential: cert(serviceAccount),
    });
    isFirebaseInitialized = true;
    console.log('Firebase Admin initialized successfully.');
  } else {
    console.warn(
      `Firebase Service Account file not found at ${serviceAccountPath}.\n` +
      'Push notification server functions will run in simulation mode.'
    );
  }
} catch (err) {
  console.error('Failed to initialize Firebase Admin SDK:', err);
}

/**
 * Sends a silent, data-only push notification to wake the client up for synchronisation.
 * Zero-trace payload: containing no plaintext content, no key agreements, and no metadata leaks.
 */
export async function sendSilentPush(pushToken: string, messageId: string): Promise<boolean> {
  if (!isFirebaseInitialized) {
    console.log(`[Push Simulation] Sending silent sync push for message ID: ${messageId} to token: ${pushToken.substring(0, 10)}...`);
    return true;
  }

  const message: Message = {
    token: pushToken,
    data: {
      type: 'sync',
      messageId: messageId,
    },
    android: {
      priority: 'high',
    },
    apns: {
      payload: {
        aps: {
          contentAvailable: true, // Required for iOS background execution
        },
      },
      headers: {
        'apns-push-type': 'background',
        'apns-priority': '5', // Background priority
        'apns-topic': 'com.chatly.app', // Update to match iOS App bundle identifier
      },
    },
  };

  try {
    const response = await getMessaging().send(message);
    console.log('Successfully sent silent sync push:', response);
    return true;
  } catch (error) {
    console.error('Failed to send FCM silent push:', error);
    return false;
  }
}
