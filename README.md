README.md:
# 💰 Smart Personal Finance Tracker

![Flutter](https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=white)
![Python](https://img.shields.io/badge/Python-3776ab?logo=python&logoColor=white)
![Flask](https://img.shields.io/badge/Flask-black?logo=flask&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169e1?logo=postgresql&logoColor=white)

A mobile-first financial management app built for Kenyan university students — a demographic global finance apps largely ignore, since most assume card-based spending and can't parse M-Pesa or cash. This reads M-Pesa confirmation SMS straight off the device to track transactions automatically, then runs them through a rule-based expert system that scores financial health and gives real advice back.

## Highlights

- Reads M-Pesa transaction SMS directly from the device inbox for automatic expense tracking — no manual entry required
- Experta rule-based expert system with 43 rules scoring financial health (0–100) and assigning a financial persona
- Flask + SQLAlchemy REST API with JWT authentication across 16 endpoints, deployed via Gunicorn
- SQLite in development, PostgreSQL in production (auto-detected from environment)
- Flutter Android frontend with pie/bar charts and a budget variance dashboard
- Biometric and PIN authentication, plus Google Sign-In
- Guardian Link module — WhatsApp/SMS alerts via Twilio on critical financial health scores, with a 24-hour cooldown to prevent spam

## Tech Stack

**Backend** — Flask, SQLAlchemy, PostgreSQL/SQLite, JWT (Flask-JWT-Extended), Experta, Twilio, Gunicorn
**Frontend** — Flutter, fl_chart, local_auth, flutter_sms_inbox, Google Sign-In

## Project Structure

smart-finance-tracker/
├── backend/
│   ├── api/
│   ├── engine/             # Experta rule-based expert system
│   ├── services/
│   ├── app.py
│   ├── models.py
│   └── migrate.py
└── frontend/                # Flutter app
    └── lib/

## Getting Started

Backend:
\`\`\`bash
cd backend
pip install -r requirements.txt
python migrate.py
python app.py
\`\`\`

Frontend:
\`\`\`bash
cd frontend
flutter pub get
flutter run
\`\`\`
