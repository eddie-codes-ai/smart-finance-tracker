import os

from flask import Flask, jsonify, request
from werkzeug.exceptions import HTTPException
from flask_cors import CORS
from flask_jwt_extended import JWTManager
from models import db
from api.routes import api

# ── Load .env file automatically ─────────────────────────────────────────────
try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass

def create_app():
    """Application factory."""
    app = Flask(__name__)

    # ── Configuration ─────────────────────────────────────────────────────────
    database_url = os.environ.get("DATABASE_URL", "sqlite:///finance_tracker.db")
    if database_url.startswith("postgres://"):
        database_url = database_url.replace("postgres://", "postgresql://", 1)

    app.config["SQLALCHEMY_DATABASE_URI"]        = database_url
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
    app.config["JWT_SECRET_KEY"]                 = os.environ.get(
        "JWT_SECRET_KEY", "change-this-secret-in-production"
    )
    app.config["JWT_ACCESS_TOKEN_EXPIRES"]       = False

    # ── Extensions ────────────────────────────────────────────────────────────
    db.init_app(app)
    _configure_jwt(JWTManager(app))
    CORS(app)

    # ── Blueprints ────────────────────────────────────────────────────────────
    app.register_blueprint(api)

    # ── Error handlers ────────────────────────────────────────────────────────
    _register_error_handlers(app)

    # ── Create tables on first run ────────────────────────────────────────────
    with app.app_context():
        db.create_all()

    return app


def _configure_jwt(jwt: JWTManager):
    """
    Make JWT rejections use the same envelope as every other error.

    flask-jwt-extended answers with {"msg": ...} by default, so the client
    would see a 401 with no readable message and fall back to a generic
    failure string. These callbacks give it {"status", "message"} instead,
    and a "token_expired" flag it can use to trigger re-authentication.
    """

    def _reject(message: str, expired: bool = False):
        payload = {"status": "error", "message": message}
        if expired:
            payload["token_expired"] = True
        return jsonify(payload), 401

    @jwt.expired_token_loader
    def _expired(_header, _payload):
        return _reject("Your session has expired. Please sign in again.", expired=True)

    @jwt.unauthorized_loader
    def _missing(_reason):
        return _reject("You need to be signed in to do that.")

    @jwt.invalid_token_loader
    def _invalid(_reason):
        return _reject("Your session is no longer valid. Please sign in again.")

    @jwt.revoked_token_loader
    def _revoked(_header, _payload):
        return _reject("Your session has been signed out. Please sign in again.")

    return jwt


def _register_error_handlers(app: Flask):
    """
    Guarantee that every response this API produces is JSON.

    Without these, an unhandled exception (or a 404, or a request with no JSON
    body) returns Werkzeug's HTML error page. The Flutter client decodes every
    response body as JSON, so an HTML error surfaced to the user as
    "Check your connection" — hiding the real cause.
    """

    @app.errorhandler(HTTPException)
    def _handle_http_exception(e: HTTPException):
        return jsonify({
            "status":  "error",
            "message": e.description or e.name,
        }), e.code

    @app.errorhandler(Exception)
    def _handle_unexpected(e: Exception):
        # Log the full traceback server-side; never leak it to the client.
        app.logger.exception("Unhandled error on %s %s", request.method, request.path)
        return jsonify({
            "status":  "error",
            "message": "Something went wrong on our end. Please try again.",
        }), 500


# ── Entry point ───────────────────────────────────────────────────────────────
if __name__ == "__main__":
    app = create_app()
    app.run(
        host  = "0.0.0.0",
        port  = int(os.environ.get("PORT", 5000)),
        debug = os.environ.get("FLASK_DEBUG", "true").lower() == "true",
    )