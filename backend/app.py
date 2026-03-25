import os
from flask import Flask
from flask_cors import CORS
from flask_jwt_extended import JWTManager
from models import db
from api.routes import api


def create_app():
    """Application factory."""
    app = Flask(__name__)

    # ── Configuration ─────────────────────────────────────────────────────────
    app.config["SQLALCHEMY_DATABASE_URI"]        = os.environ.get(
        "DATABASE_URL", "sqlite:///finance_tracker.db"
    )
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
    app.config["JWT_SECRET_KEY"]                 = os.environ.get(
        "JWT_SECRET_KEY", "change-this-secret-in-production"
    )
    app.config["JWT_ACCESS_TOKEN_EXPIRES"]       = False  # tokens don't expire (suitable for mobile)

    # ── Extensions ────────────────────────────────────────────────────────────
    db.init_app(app)
    JWTManager(app)
    CORS(app)  # allow Flutter app to call the API from any origin

    # ── Blueprints ────────────────────────────────────────────────────────────
    app.register_blueprint(api)

    # ── Create tables on first run ────────────────────────────────────────────
    with app.app_context():
        db.create_all()

    return app
#chabge

# ── Entry point ───────────────────────────────────────────────────────────────
if __name__ == "__main__":
    app = create_app()
    app.run(
        host  = "0.0.0.0",
        port  = int(os.environ.get("PORT", 5000)),
        debug = os.environ.get("FLASK_DEBUG", "true").lower() == "true",
    )