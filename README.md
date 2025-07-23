# Aexlrt (testingheartrate)

A Flutter app for interactive audio-based fitness adventures, featuring story-driven challenges, heart rate tracking, advanced analytics, and seamless user experience. This documentation covers all technical details, APIs, and app workflows to help developers and maintainers onboard and contribute efficiently.

---

## Table of Contents

* [Features](#features)
* [Project Structure](#project-structure)
* [Authentication](#authentication)
* [API Endpoints](#api-endpoints)
* [Screens & Navigation](#screens--navigation)
* [Socket Service](#socket-service)
* [Audio Management](#audio-management)
* [Challenge Flow](#challenge-flow)
* [Profile & History](#profile--history)
* [Assets](#assets)
* [Development](#development)
* [License](#license)
* [Contact](#contact)

---

## Features

* **Apple Sign-In & Email Authentication**

  * Secure, production-ready OAuth flows via `sign_in_with_apple` (iOS) and email/password authentication with JWT tokens.
  * All authentication tokens are encrypted and stored using `SharedPreferences` and never exposed in logs or UI.
* **Story-based Fitness Challenges**

  * Immersive, character-driven workouts with selectable zone and time, integrated with personalized audio journeys.
* **Audio-guided Workouts & Offline Download**

  * Uses `just_audio` and `audio_service` for robust background playback, auto-caching, and resuming.
* **Real-time Heart Rate Tracking**

  * Live heart rate stream from Apple Watch, visualized during workouts, and used for post-challenge analytics.
* **Challenge Analytics**

  * Advanced analytics and feedback for each challenge: zone time, heart rate ranges, nudges, completion stats.
* **User Profile & History**

  * Edit/view user profile. Review challenge history and analytics from previous sessions.
* **Firebase Analytics**

  * In-depth event and screen analytics for user flows and challenge completions.
* **Production-ready Error Handling**

  * Comprehensive try/catch, error dialogs, loading states, and crash reporting integrated throughout the app.

---

## Project Structure

```text
lib/
  main.dart                  # App entrypoint, app-wide state
  firebase_options.dart      # Firebase config for different environments
  providers/
    auth_provider.dart       # Handles authentication state & token management
  screens/
    auth/                   # Login, signup, and Apple auth screens
    audioplayer/            # Audio player and challenge player screens
    challenge/              # Challenge selection, story, and onboarding
    completion/             # Post-challenge analytics and completion summary
    history/                # User challenge history
    home/                   # Landing and character select
    profile/                # Profile viewing and editing
    splash/                 # Splash and auth state checking
    speed/                  # Speed measurement (optional, GPS/steps)
    leaderboard/            # Leaderboard and stats (if enabled)
  services/
    audio_manager.dart              # Handles audio download, caching, playback queue
    socket_service.dart             # Real-time data (heart rate, challenge progress)
    firebase_notification.dart      # Push notification setup (Firebase Messaging)
    gps_service.dart                # GPS, motion, and location data
    kalman_filter.dart              # Sensor data smoothing for step/speed (if enabled)
    motion_detection_service.dart   # Motion/step detection
    steps_service.dart              # Step count (if enabled)
    time_tracking_service.dart      # Time and challenge session management
assets/
  images/
  audio/
  videos/
pubspec.yaml   # Asset and package configuration
```

---

## Authentication

### Apple Sign-In

* Utilizes `sign_in_with_apple` for iOS.
* Exchanges Apple ID token for JWT, verified server-side at `/auth` endpoint.
* On success, securely stores received token in `SharedPreferences`.
* Refresh tokens and automatic login restoration on app start.
* User's private Apple ID/email never exposed beyond local device.

### Email/Password

* Credentials are POSTed securely to `/emailauth` endpoint.
* Token received is validated, encrypted, and persisted in `SharedPreferences`.
* Auth state and error handling is centralized in `auth_provider.dart`.
* Secure logout and token revocation handled.

### Secure Token Handling

* All API requests requiring authentication set the `Authorization: Bearer <token>` header.
* Tokens never logged or exposed in UI for maximum security.
* Uses `Provider` or `Riverpod` for state and dependency injection.

---

## API Endpoints

All endpoints are under `https://authcheck.co`. All endpoints use HTTPS and JWT Bearer Auth (where required).

### Auth

| Endpoint     | Method | Description            | Headers / Body Example   |
| ------------ | ------ | ---------------------- | ------------------------ |
| `/auth`      | POST   | Apple Sign-In          | `{ token, name, email }` |
| `/emailauth` | POST   | Email/Password Sign-In | `{ email, password }`    |

### User

| Endpoint      | Method | Description         | Headers / Body Example          |
| ------------- | ------ | ------------------- | ------------------------------- |
| `/getuser`    | GET    | Get user profile    | `Authorization: Bearer <token>` |
| `/updateuser` | POST   | Update user profile | `{ name, age, gender }`         |
| `/deleteuser` | POST   | Delete user account | `Authorization: Bearer <token>` |

### Challenges

| Endpoint           | Method | Description                  | Headers / Body Example                 |
| ------------------ | ------ | ---------------------------- | -------------------------------------- |
| `/getChallenges`   | GET    | Get all available challenges | `Authorization: Bearer <token>`        |
| `/userchallenge`   | GET    | User's completed challenges  | `Authorization: Bearer <token>`        |
| `/startchallenge`  | POST   | Start a challenge            | `{ challengeId: [int], zoneId: int }`  |
| `/updatechallenge` | POST   | Mark challenge as completed  | `{ challengeId: [int], status: true }` |

### Analytics

| Endpoint   | Method | Description             | Headers / Body Example                |
| ---------- | ------ | ----------------------- | ------------------------------------- |
| `/analyse` | POST   | Analyse heart rate data | `{ challengeId: [int], zoneId: int }` |

#### Error Handling & Retry

* All API calls are wrapped with retry logic and error parsing.
* Failures are surfaced to the UI with actionable messages and retry/refresh options.

---

## Screens & Navigation

### SplashScreen

* Loads on app start; checks token in storage.
* Navigates to `HomeScreen` if authenticated, else to `AuthScreen`.

### AuthScreen

* Apple Sign-In for iOS, Email/Password for Android.
* Handles onboarding and error flows (invalid credentials, network error).
* On success, navigates to `HomeScreen`.

### HomeScreen

* Shows character selection (carousel, grid, or scroll).
* Displays available challenges, completion state, and call-to-action for each character.
* Persistent bottom navigation (Home, History, Profile).
* Uses Provider or Riverpod for state management.

### ChallengeScreen

* Story-driven UI, shows challenge description, story, zones, and durations.
* Zone selection (Walk/Jog/Run) and time (5–60 minutes, increments).
* Downloads and caches audio files if required (with progress indicator).
* Starts challenge (calls `/startchallenge` API) and transitions to `PlayerScreen`.

### PlayerScreen

* Audio player UI with play/pause/seek, progress bar, and challenge metrics.
* Real-time heart rate display (via Socket Service).
* Handles audio interruption/resume and challenge pause/resume.
* On completion, posts challenge data and moves to `CompletionScreen`.

### CompletionScreen

* Fetches challenge analytics from `/analyse`.
* Shows heart rate stats, zone breakdown, feedback, and suggestions.
* Option to share achievement and view more analytics.

### HistoryScreen

* List of all completed challenges, sortable/filterable.
* Tapping a challenge shows analytics summary.

### ProfilePage

* Displays user info (name, age, gender, email).
* Allows updating profile or account deletion.
* Handles logout with confirmation and token clearing.

---

## Socket Service

* Real-time communication for heart rate and challenge data.
* Connects to `wss://authcheck.co` using JWT `Authorization` header.
* Subscribes to `watchdataSaved` event for heart rate updates.
* Exposes methods:

  * `fetechtoken()` for retrieving token from storage.
  * `dispose()` for graceful disconnection.
* Handles reconnects, exponential backoff, and emits connection status for UI.
* All heart rate and live data is sanitized, validated, and time-synced before processing.

---

## Audio Management

* Manages audio playlist for challenge with `just_audio` and `audio_service`.
* Downloads required audio files before challenge if not cached.
* Uses robust caching (directory per challenge, cleanup on app uninstall or user logout).
* Handles playlist sequencing, skip/seek, and interruption recovery.
* Progress, buffer status, and playback state are exposed for UI.

---

## Challenge Flow

**Production-ready flow:**

1. **Select Character**: User picks from available characters (data from `/getChallenges`).
2. **Select Zone**: Choose Walk/Jog/Run.
3. **Select Duration**: 5–60 min (configurable).
4. **Audio Download**: Checks/downloads audio assets as needed (with progress UI).
5. **Start Challenge**: Posts to `/startchallenge`, initializes challenge state.
6. **Play Audio**: In `PlayerScreen` with full playback controls and heart rate tracking.
7. **Track Heart Rate**: Real-time updates via Socket Service.
8. **Complete Challenge**: Marks challenge as complete with `/updatechallenge`.
9. **Show Analytics**: Presents results and deep insights (`/analyse`).
10. **Save to History**: Automatically logged for user in `HistoryScreen`.

---

## Profile & History

* **ProfilePage**: Allows profile update, logout, account deletion. Secure and user-verified operations only.
* **HistoryScreen**: View, filter, and inspect all previous challenges. Tapping shows analytics for that session.
* Challenge analytics and results are available even offline (local cache).

---

## Assets

* All assets (images, audio, video) are managed in `pubspec.yaml` and loaded with proper path and caching strategy.
* Assets are versioned for cache invalidation on update.

---

## Development

### Requirements

* Flutter 3.5.4+ (null-safety required)
* Firebase account (for analytics, messaging, remote config)
* Apple Developer account (for Apple Sign-In, Apple Watch integration)
* Android/iOS device or simulator/emulator
* Access to API base URL and keys (for production deployment)

### Run

```sh
flutter pub get
flutter run
```

### Debugging & Testing

* Use `flutter run --debug` for live reloading.
* In-depth logging enabled in debug mode only; no PII logged in release.
* Widget, integration, and e2e tests are placed in `/test` and `/integration_test` folders.
* All services and providers are easily mockable for testing.

### CI/CD

* Project is CI/CD-ready (can be extended for GitHub Actions, Codemagic, or Bitrise).
* Build variants for dev/staging/prod with different `firebase_options.dart`.

---

## License

This project is for educational/demo purposes. See LICENSE file for terms.

---

## Contact

For technical questions, feature requests, or contributions, open a GitHub issue or contact the maintainer via email.
