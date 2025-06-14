# Aexlrt (testingheartrate)

A Flutter app for interactive audio-based fitness adventures, featuring story-driven challenges, heart rate tracking, and user analytics.

---

## Table of Contents

- [Features](#features)
- [Project Structure](#project-structure)
- [Authentication](#authentication)
- [API Endpoints](#api-endpoints)
- [Screens & Navigation](#screens--navigation)
- [Socket Service](#socket-service)
- [Audio Management](#audio-management)
- [Challenge Flow](#challenge-flow)
- [Profile & History](#profile--history)
- [Assets](#assets)
- [Development](#development)
- [License](#license)

---

## Features

- **Apple Sign-In & Email Authentication**
- **Story-based fitness challenges** (select character, zone, duration)
- **Audio-guided workouts**
- **Heart rate tracking (via Apple Watch)**
- **Challenge completion analytics**
- **User profile & history**
- **Offline audio download**
- **Firebase Analytics integration**

---

## Project Structure

```
lib/
  main.dart
  firebase_options.dart
  providers/
    auth_provider.dart
  screens/
    auth/
    audioplayer/
    challenge/
    completion/
    history/
    home/
    profile/
    splash/
  services/
    audio_manager.dart
    socket_service.dart
assets/
  images/
  audio/
  videos/
```

---

## Authentication

### Apple Sign-In

- Uses `sign_in_with_apple` for iOS.
- Stores `token` in `SharedPreferences` on success.

### Email/Password

- POST to `/emailauth` with JSON `{ email, password }`.
- Stores `token` in `SharedPreferences` on success.

---

## API Endpoints

All endpoints are under `https://authcheck.co`.

### Auth

| Endpoint         | Method | Description                        | Headers / Body Example                      |
|------------------|--------|------------------------------------|---------------------------------------------|
| `/auth`          | POST   | Apple Sign-In                      | `{ token, name, email }`                    |
| `/emailauth`     | POST   | Email/Password Sign-In             | `{ email, password }`                       |

### User

| Endpoint         | Method | Description                        | Headers / Body Example                      |
|------------------|--------|------------------------------------|---------------------------------------------|
| `/getuser`       | GET    | Get user profile                   | `Authorization: Bearer <token>`             |
| `/updateuser`    | POST   | Update user profile                | `{ name, age, gender }`                     |
| `/deleteuser`    | POST   | Delete user account                | `Authorization: Bearer <token>`             |

### Challenges

| Endpoint             | Method | Description                        | Headers / Body Example                      |
|----------------------|--------|------------------------------------|---------------------------------------------|
| `/getChallenges`     | GET    | Get all available challenges       | `Authorization: Bearer <token>`             |
| `/userchallenge`     | GET    | Get user's completed challenges    | `Authorization: Bearer <token>`             |
| `/startchallenge`    | POST   | Start a challenge                  | `{ challengeId: [int], zoneId: int }`       |
| `/updatechallenge`   | POST   | Mark challenge(s) as completed     | `{ challengeId: [int], status: true }`      |

### Analytics

| Endpoint         | Method | Description                        | Headers / Body Example                      |
|------------------|--------|------------------------------------|---------------------------------------------|
| `/analyse`       | POST   | Analyse heart rate data            | `{ challengeId: [int], zoneId: int }`       |

---

## Screens & Navigation

### SplashScreen

- Checks authentication state and routes to `HomeScreen` or `AuthScreen`.

### AuthScreen

- Apple Sign-In (iOS) or Email/Password (Android).
- On success, navigates to `HomeScreen`.

### HomeScreen

- Character selection carousel.
- Shows challenge count per character.
- Tap character to start challenge flow.
- Bottom navigation: Home, History, Profile.

### ChallengeScreen

- Shows story, description, and available challenges.
- Zone selection (Walk/Jog/Run).
- Workout duration selection.
- Downloads audio if needed.
- Starts challenge and navigates to `PlayerScreen`.

### PlayerScreen

- Plays audio playlist for the challenge.
- Tracks progress.

### CompletionScreen

- Shows challenge analytics (heart rate, zone time, nudges).
- Fetches and displays completion data from `/analyse`.

### HistoryScreen

- Lists all completed challenges for the user.

### ProfilePage

- Displays user info.
- Allows logout and account deletion.

---

## Socket Service

Handles real-time heart rate data via socket.io.

- Connects to `wss://authcheck.co` with `Authorization` header.
- Listens for `watchdataSaved` event for heart rate updates.
- Exposes:
  - `fetechtoken()`
  - `dispose()`

---

## Audio Management

- Uses `just_audio` and `audio_service`.
- Audio files are downloaded and cached locally.
- Playlist is dynamically built per challenge.

---

## Challenge Flow

1. **Select Character** (HomeScreen)
2. **Select Zone** (Walk/Jog/Run)
3. **Select Duration** (5–60 min, in 5-min increments)
4. **Download Audio** (if not cached)
5. **Start Challenge** (`/startchallenge`)
6. **Play Audio** (PlayerScreen)
7. **Track Heart Rate** (SocketService)
8. **Complete Challenge** (`/updatechallenge`)
9. **Show Analytics** (`/analyse`)

---

## Profile & History

- **ProfilePage**: View/update user info, logout, delete account.
- **HistoryScreen**: View all completed challenges.

---

## Assets

- All images, audio, and video assets are listed in [`pubspec.yaml`](pubspec.yaml).

---

## Development

### Requirements

- Flutter 3.5.4+
- Firebase account (for analytics)
- Apple Developer account (for Apple Sign-In)

### Run

```sh
flutter pub get
flutter run
```

---

## License

This project is for educational/demo purposes.

---

## Contact

For questions or contributions, open an issue or contact the maintainer.
