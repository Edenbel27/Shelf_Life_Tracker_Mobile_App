# Shelf Life Tracker

A Flutter + Firebase mobile app for small retailers to track stock levels, expiry windows, and daily profitability with role-based access for store owners and staff.

## Features
- Role-aware navigation (owner vs staff) with pending-staff approval workflow.
- Email/password and Google sign-in backed by Firebase Authentication.
- Inventory with real-time Firestore updates: quantity, pricing, expiry days, and alert thresholds.
- Quick purchase (restock) and sale recording with validation and batch writes.
- Dashboard cards for low stock, near-expiry, expired items, and today’s profit snapshot.
- Notifications for expiry/low-stock plus owner-only approval alerts.
- Reports: last-24h profit, top sellers, and daily snapshot saving to Firestore.
- Staff management (approve/reject/remove) and user profile updates.

## Tech Stack
- Flutter (Dart 3.6)
- Firebase: Auth, Firestore, Core
- Shared Preferences (local seed user support)

## Prerequisites
- Flutter SDK installed and on PATH (Flutter 3.x recommended)
- Dart 3.6+
- Firebase project with Firestore and Authentication (Email/Password + Google) enabled
- Android/iOS tooling set up (Xcode for iOS, Android SDK/Studio for Android)

## Setup
1) Install dependencies  
```bash
flutter pub get
```

2) Firebase configuration  
- Create a Firebase project and enable Firestore + Auth (Email/Password, Google).  
- Generate platform configs:  
	- Android: place `google-services.json` in `android/app/`.  
	- iOS: place `GoogleService-Info.plist` in `ios/Runner/`.  
- (Re)generate `lib/firebase_options.dart` with FlutterFire CLI if project settings change:  
```bash
dart run flutterfire_cli configure
```

3) Firestore rules (basic starting point; tighten for production)  
```
// Example (adjust to your security needs)
rules_version = '2';
service cloud.firestore {
	match /databases/{database}/documents {
		match /{document=**} {
			allow read, write: if request.auth != null;
		}
	}
}
```

## Running
```bash
flutter run
```
Pick your device/emulator when prompted.

## Data Model (Firestore)
- `users`: firstName, lastName, phone, email, role (`owner`|`staff`), approved (bool), createdVia.
- `inventory`: name, nameLower, category, quantity, purchasePrice, sellingPrice, alertThresholdDays, expiresInDays, createdAt.
- `transactions`: itemId, name, category, type (`sale`|`purchase`), qty, amount, purchasePrice, sellingPrice, timestamp.
- `daily_reports`: date (YYYY-MM-DD), totalSales, totalPurchases, profit, transactions, createdAt.

## Roles & Flow
- Owner: full access to approvals, reporting, purchases, sales, and staff removal. Seed at least one owner user in Auth + Firestore (`role: owner`, `approved: true`).
- Staff: sign up via email or Google → awaits owner approval before accessing the app.

## Key Screens
- Splash → Login/Signup (email + Google)  
- Home dashboard (stats, quick actions)  
- Inventory list with filters and inline edit/delete (owner)  
- Purchase entry (add/merge inventory) and Sales entry  
- Transactions history (recent, filterable)  
- Reports (24h profit, top sellers, snapshot)  
- Notifications (expiry/low-stock + pending approvals)  
- Settings (profile, password, staff management for owner)

## Testing
```bash
flutter test
```

## Troubleshooting
- Firebase init errors: verify `google-services.json` / `GoogleService-Info.plist` and `firebase_options.dart` match your Firebase project.
- Auth failures: ensure Email/Password and Google providers are enabled in Firebase console.
- Permission errors: update Firestore security rules for your environment.
adb kill-server
adb start-server
adb devices