# 💰 Smart Personal Finance Tracker

![Flutter](https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=white)
![Python](https://img.shields.io/badge/Python-3776ab?logo=python&logoColor=white)
![Flask](https://img.shields.io/badge/Flask-black?logo=flask&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169e1?logo=postgresql&logoColor=white)

A mobile-first financial management app built for Kenyan university students — a demographic global finance apps largely ignore, since most assume card-based spending and can't parse M-Pesa or cash. This reads M-Pesa confirmation SMS straight off the device to track transactions automatically, then runs them through a rule-based expert system that scores financial health and gives real advice back.

## Highlights

- Reads M-Pesa transaction SMS directly from the device inbox for automatic expense tracking — no manual entry required, with duplicate detection so the same message can't be imported twice
- Experta rule-based expert system with 55 rules scoring financial health (0–100) and assigning a financial persona, across ten independent dimensions: savings rate, spending pace, emergency fund, daily discipline, overspending persistence, discretionary spending, budget adherence, goal pacing, goal realism, and month-over-month direction
- Flask + SQLAlchemy REST API across 44 endpoints, with expiring JWT sessions, silent token refresh, and server-side revocation on logout or password change
- Per-user time zones — months and daily spending are grouped in the user's own zone, so figures stay correct when travelling
- SQLite in development, PostgreSQL in production (auto-detected from environment), with Alembic migrations
- Flutter Android frontend with pie/bar charts and a budget variance dashboard
- Biometric app lock (fingerprint, face, or device screen lock), plus Google Sign-In
- Guardian Link module — WhatsApp/SMS alerts via Twilio on critical financial health scores, with a 24-hour cooldown to prevent spam

## Tech Stack

**Backend** — Flask, SQLAlchemy, Alembic (Flask-Migrate), PostgreSQL/SQLite, JWT (Flask-JWT-Extended), Experta, google-auth, Twilio, Gunicorn
**Frontend** — Flutter, fl_chart, local_auth, flutter_sms_inbox, flutter_timezone, Google Sign-In

## Project Structure

```
smart-finance-tracker/
├── backend/
│   ├── api/                # REST routes
│   ├── engine/             # Experta rule-based expert system
│   ├── services/           # analysis, email, guardian, notifications
│   ├── migrations/         # Alembic revisions
│   ├── tests/              # runnable with the project venv, no pytest needed
│   ├── app.py              # application factory
│   ├── app_time.py         # every timezone decision lives here
│   └── models.py
└── frontend/               # Flutter app
    ├── lib/
    └── test/
```

## Getting Started

### Backend

```bash
cd backend
python -m venv venv
venv/Scripts/activate          # Windows;  source venv/bin/activate elsewhere
pip install -r requirements.txt
```

Copy `.env.example` to `.env` and fill it in. Then create the schema and run:

```bash
set FLASK_APP=app:create_app   # Windows;  export FLASK_APP=... elsewhere
flask db upgrade
python app.py
```

`flask db upgrade` is how the schema is created and updated — Alembic owns it.
`migrate.py` is a deprecated stub kept only to point at the right command.

Python **3.9** is required: Experta does not work on newer versions, which is
why the Dockerfile pins `python:3.9-slim`.

### Frontend

```bash
cd frontend
flutter pub get
flutter run
```

The app defaults to `http://localhost:5000/api`. On a USB-connected phone or an
emulator, forward the port once per connection:

```bash
adb reverse tcp:5000 tcp:5000
```

Or point it somewhere else without editing code:

```bash
flutter run --dart-define=API_BASE_URL=https://your-host/api
```

Plain `http://` only works in debug builds — see
`android/app/src/debug/res/xml/network_security_config.xml`.

## Tests

167 tests, none of which need pytest or any extra dependency.

```bash
cd backend
venv/Scripts/python tests/test_engine_scoring.py     # and the other 7 files
```

```bash
cd frontend
flutter test
```

| Suite | Covers |
|---|---|
| `test_error_contract` | every failure returns JSON, never an HTML error page |
| `test_transaction_updates` | editing preserves the original date; ownership is enforced |
| `test_timezone` | month boundaries in local time, not UTC |
| `test_user_timezone` | two users in different countries, same stored row |
| `test_auth_security` | reset-code attempt limits, login throttling |
| `test_mpesa_import` | duplicate imports refused, SMS date preserved |
| `test_engine_scoring` | golden scenarios and score calibration |
| `test_session_lifecycle` | expiry, refresh, revocation |

## Notes

- Release builds are currently signed with the debug keystore. A real signing
  config is needed before distribution.
- Google Sign-In requires an Android OAuth client in Google Cloud Console
  carrying the SHA-1 of whichever key signs the APK.
