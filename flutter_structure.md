# Fabio Pay — Flutter Architecture & Design Guide

## 1. Application Structure

The Flutter application is structured around a simple, clean architecture without over-engineering (no complex state management libraries like Riverpod/Bloc are used intentionally, relying instead on `setState` for localized state and singletons for global services).

```
frontend/
├── lib/
│   ├── config/          # Centralized configuration (API URLs, Theme, Colors)
│   ├── models/          # Dart models with JSON serialization
│   ├── screens/         # UI Screens (Login, Dashboard, Admin, etc.)
│   ├── services/        # Singleton services (ApiService, AuthService)
│   ├── widgets/         # Reusable UI components (GlassCard, FabButton)
│   └── main.dart        # Entry point and routing table
```

## 2. Global Services

### `AuthService` (Secure Storage)
Handles persistence of the opaque session token and cached user profile using `flutter_secure_storage`.
- **Token**: Saved upon login, deleted on logout or 401 error.
- **User Profile**: Cached JSON to allow immediate rendering while fetching updates.

### `ApiService` (Dio HTTP Client)
All network requests are routed through this singleton.
- **Interceptors**: Automatically attaches `Authorization: Bearer <token>` to every request.
- **Global 401 Handling**: If *any* request returns a `401 Unauthorized`, the interceptor (or specific screen logic) auto-routes the user back to `/login` and clears local storage.

## 3. Risk-Based Routing & Liveness (Biometrics)

The core feature of Fabio Pay is its dynamic, risk-based authentication flow for transactions.

1. **Transfer Form**: User enters amount.
2. **Evaluation**: If amount < `threshold_amount` (Settings), standard PIN auth is triggered.
3. **High-Risk Route**: If amount >= `threshold_amount`, the user is routed to `/liveness`.
4. **WebSocket Streaming**:
   - Connects to `/ws/liveness` with the session token.
   - Streams base64-encoded JPEG frames from the front camera.
   - Backend evaluates Active Liveness (MediaPipe Blink/Smile) + Identity Verification (Face Mesh landmarks).
   - Upon `PASSED` challenge, the UI completes the transfer.

## 4. Role-Based Access Control (RBAC)

Routing is determined by the `user.role` returned by the `/api/users/me` endpoint.

- **SplashScreen**: Checks if logged in. If yes, fetches `/api/users/me`.
  - Routes to `/admin` if role is `ADMIN` or `VICE_ADMIN`.
  - Routes to `/dashboard` if role is `USER`.
- **LoginScreen**: Applies the same routing logic immediately after successful login.
- **Admin Dashboard**: Contains dedicated charts, user lists, and session revocation tools, protected on the backend by `@require_role`.

## 5. UI/UX "Glassmorphism" Design System

The application uses a custom "Glassmorphism" design system tailored for FinTech applications to look premium and modern.

- **Background**: Deep gradient (`#0A0E17` to `#1A233A`).
- **Cards**: `GlassCard` widget uses semi-transparent white fills with a subtle border to create depth.
- **Typography**: Inter / Roboto based (default Material typography), heavily utilizing font-weights.
- **Colors**:
  - Primary: `#4F46E5` (Indigo)
  - Accent: `#06B6D4` (Cyan)
  - Success: `#10B981` (Emerald)
  - Error: `#EF4444` (Red)
