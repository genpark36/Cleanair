# CleanAir Web Dashboard

This is a lightweight control-room dashboard for the current Firebase project.

## Setup

1. Copy `firebase-config.example.js` to `firebase-config.js`.
2. Fill the Firebase Web app config from Firebase Console.
3. Serve this folder with a local static server or Firebase Hosting.

No backend secrets belong in this folder. The dashboard reads public Firestore
collections used by the app and calls existing public Cloud Functions for plug
control.

## Login

The dashboard uses Firebase Auth Google login. For a quick demo, an empty
`adminEmails` list allows any signed-in Firebase user. To restrict access, add
manager emails in `firebase-config.js`.

Firebase Console requirements:

- Authentication > Sign-in method > Google enabled
- Authentication > Settings > Authorized domains includes the hosting domain

## Current Features

- Live sensor overview from `sensors`
- Live alert timeline from `alerts`
- Smart plug list/control through `listPlugs` and `commandPlug`
- Critical alert banner and detail modal
- Facility status cards and map-style situation board
- Device control panel for manual ON/OFF

## Next Integration Step

For a real fire-station or central-control deployment, add Firebase Auth and
limit Firestore/Function access by organization or facility. The current version
is suitable for the capstone demo path and keeps the app pipeline unchanged.
