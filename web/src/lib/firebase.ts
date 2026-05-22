let app: any = null;

export async function getFirebase() {
  if (typeof window === "undefined") return null;

  try {
    const firebase = await import("firebase/app");
    if (!firebase.getApps().length) {
      app = firebase.initializeApp({
        apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY
      });
    }
    return app;
  } catch {
    return null;
  }
}
