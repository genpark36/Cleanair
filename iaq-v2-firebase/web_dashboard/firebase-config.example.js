// Copy this file to firebase-config.js and fill the values from Firebase Console.
// Firebase Console > Project settings > Your apps > Web app config.
window.CLEANAIR_FIREBASE_CONFIG = {
  apiKey: "YOUR_FIREBASE_WEB_API_KEY",
  authDomain: "YOUR_PROJECT_ID.firebaseapp.com",
  projectId: "YOUR_PROJECT_ID",
  storageBucket: "YOUR_PROJECT_ID.firebasestorage.app",
  messagingSenderId: "YOUR_SENDER_ID",
  appId: "YOUR_WEB_APP_ID",
};

window.CLEANAIR_DASHBOARD_OPTIONS = {
  defaultRegion: "us-central1",
  requireAuth: true,
  // Empty list allows any signed-in Firebase user for quick capstone demos.
  // Add emails here to limit access:
  // adminEmails: ["your-email@gmail.com"],
  adminEmails: [],
  // Existing Functions require the same X-API-Key used by the Flutter app.
  deviceApiKey: "YOUR_DEVICE_API_KEY",
  // Optional. If omitted, the dashboard calls:
  // https://us-central1-${projectId}.cloudfunctions.net/{endpoint}
  functionsBaseUrl: "",
};
