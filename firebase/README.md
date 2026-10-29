# Firebase Setup (requires your own Firebase account)

## 1. Create the project
1. Open https://console.firebase.google.com and create a project (e.g. `leadpilot-ai`).
2. **Build → Authentication → Sign-in method**: enable **Email/Password**.
3. **Build → Firestore Database**: create a database (production mode).

## 2. Deploy rules and indexes
```bash
npm install -g firebase-tools
firebase login
cd firebase
firebase use --add          # select your project (creates .firebaserc, git-ignored)
firebase deploy --only firestore
```

## 3. Backend service account (server-side only)
1. **Project settings → Service accounts → Generate new private key**.
2. Save the file as `secrets/firebase-sa.json` at the repo root (git-ignored).
3. Set `FIREBASE_PROJECT_ID` in `backend/.env`.
4. Never commit this file or paste it into chat.

## 4. Connect the Flutter app
```bash
dart pub global activate flutterfire_cli
cd mobile
flutterfire configure       # generates lib/firebase_options.dart
```

## 5. Optional: local emulators
```bash
cd firebase
firebase emulators:start --only auth,firestore
```

## Access model summary
- Clients read data only for workspaces where they are an active member.
- Clients may create/edit basic lead fields, follow-ups, and notes (roles: owner, admin, agent).
- Qualification results, status changes, approvals, bookings, executions, usage, audit logs, workspaces, and memberships are written **only** by the backend.
- No API keys or credentials are stored in Firestore.