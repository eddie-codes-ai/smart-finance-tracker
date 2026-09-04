import json
import secrets
from datetime import datetime, timedelta
from flask_sqlalchemy import SQLAlchemy
from werkzeug.security import generate_password_hash, check_password_hash

from app_time import DEFAULT_TIMEZONE_NAME, iso_utc, utc_now

db = SQLAlchemy()

# ─── Constants ────────────────────────────────────────────────────────────────

EXPENSE_TYPES       = ('daily', 'monthly', 'one-time', 'recurring')
RECURRENCE_CHOICES  = ('daily', 'weekly', 'biweekly', 'monthly')

# Default categories — permanent, cannot be deleted by users.
DEFAULT_EXPENSE_CATEGORIES = (
    'Food', 'Transport', 'Entertainment', 'Shopping',
    'Health', 'Education', 'Utilities', 'Rent', 'Other'
)

# Default income types — permanent, cannot be deleted by users.
DEFAULT_INCOME_TYPES = (
    'monthly', 'daily', 'helb', 'parental', 'gig', 'other'
)

TRIGGER_CHOICES      = ('auto', 'manual')
DELETION_GRACE_HOURS = 96


# ─── User ─────────────────────────────────────────────────────────────────────

class User(db.Model):
    __tablename__ = "users"

    id                    = db.Column(db.Integer,    primary_key=True)
    username              = db.Column(db.String(80), unique=True,  nullable=False)
    password_hash         = db.Column(db.String(256),              nullable=False)
    email                 = db.Column(db.String(120), unique=True,  nullable=True)
    google_id             = db.Column(db.String(100), unique=True,  nullable=True)
    # The user's HOME zone, as an IANA name. Deliberately not the device's
    # current zone: month boundaries follow this, so travelling must not
    # re-bucket a user's existing history.
    timezone              = db.Column(db.String(64), nullable=False,
                                      default=DEFAULT_TIMEZONE_NAME,
                                      server_default=DEFAULT_TIMEZONE_NAME)
    # A scrypt hash of the reset code, never the code itself: the column used to
    # hold the six digits in plaintext, so any read of this table was an
    # account takeover. Wide enough for the hash format werkzeug produces.
    reset_token           = db.Column(db.String(255),              nullable=True)
    reset_token_expiry    = db.Column(db.DateTime,                  nullable=True)

    # Wrong guesses against the current reset code. The code is only six digits,
    # so a cap on attempts - not the code's own entropy - is what actually
    # stops it being guessed.
    reset_attempts        = db.Column(db.Integer, nullable=False,
                                      default=0, server_default="0")

    # Consecutive failed password logins, and the time password login reopens.
    failed_login_attempts = db.Column(db.Integer, nullable=False,
                                      default=0, server_default="0")
    locked_until          = db.Column(db.DateTime,                  nullable=True)

    # Stamped into every token this user is issued and checked on each request.
    # Bumping it invalidates every token they hold at once, which is how logout,
    # a password change and a password reset can actually end a session - with
    # no blocklist table to store or prune. Without it a stolen token survived
    # the victim changing their password, which made the reset flow useless
    # against the attack it exists to stop.
    token_version         = db.Column(db.Integer, nullable=False,
                                      default=0, server_default="0")
    deletion_requested_at = db.Column(db.DateTime,                  nullable=True)
    created_at            = db.Column(db.DateTime, default=utc_now, nullable=False)

    incomes            = db.relationship("Income",         backref="owner", lazy=True, cascade="all, delete-orphan")
    expenses           = db.relationship("Expense",        backref="owner", lazy=True, cascade="all, delete-orphan")
    budgets            = db.relationship("Budget",         backref="owner", lazy=True, cascade="all, delete-orphan")
    savings_goals      = db.relationship("SavingsGoal",    backref="owner", lazy=True, cascade="all, delete-orphan")
    guardian           = db.relationship("Guardian",       backref="user",  uselist=False, cascade="all, delete-orphan")
    guardian_reports   = db.relationship("GuardianReport", backref="user",  lazy=True, cascade="all, delete-orphan")
    helb_plan          = db.relationship("HelbPlan",       backref="user",  uselist=False, cascade="all, delete-orphan")
    custom_categories  = db.relationship("UserCategory",   backref="user",  lazy=True, cascade="all, delete-orphan")
    custom_income_types = db.relationship("UserIncomeType", backref="user", lazy=True, cascade="all, delete-orphan")

    def set_password(self, password: str):
        self.password_hash = generate_password_hash(password)

    def check_password(self, password: str) -> bool:
        return check_password_hash(self.password_hash, password)

    # ── Password reset codes ─────────────────────────────────────────────────

    def issue_reset_code(self, ttl_minutes: int) -> str:
        """
        Mint a fresh reset code, store only its hash, and return the plaintext
        for the email.

        secrets, not random: random is a Mersenne Twister, whose future output
        is derivable from enough past output, which is disqualifying for
        anything that grants account access.
        """
        code = f"{secrets.randbelow(1_000_000):06d}"
        self.reset_token        = generate_password_hash(code)
        self.reset_token_expiry = utc_now() + timedelta(minutes=ttl_minutes)
        self.reset_attempts     = 0
        return code

    def clear_reset_code(self):
        self.reset_token        = None
        self.reset_token_expiry = None
        self.reset_attempts     = 0

    def check_reset_code(self, code: str) -> bool:
        """Constant-time comparison against the stored hash."""
        if not self.reset_token:
            return False
        return check_password_hash(self.reset_token, code)

    # ── Login throttling ─────────────────────────────────────────────────────

    @property
    def is_locked_out(self) -> bool:
        return self.locked_until is not None and self.locked_until > utc_now()

    def register_failed_login(self, max_attempts: int, lockout_minutes: int):
        """
        Count a failed password attempt and lock the account once the budget is
        spent.

        The threshold is deliberately generous. Locking after two or three
        failures would let anyone who knows a username deny that person access
        at will, which trades one attack for another.
        """
        self.failed_login_attempts = (self.failed_login_attempts or 0) + 1
        if self.failed_login_attempts >= max_attempts:
            self.locked_until          = utc_now() + timedelta(minutes=lockout_minutes)
            self.failed_login_attempts = 0

    def clear_login_failures(self):
        self.failed_login_attempts = 0
        self.locked_until          = None

    # ── Sessions ─────────────────────────────────────────────────────────────

    def revoke_all_sessions(self):
        """
        Invalidate every token this user currently holds.

        Called on logout, password change and password reset. The last is the
        important one: someone who changes their password because they suspect
        a compromise expects that to end the intruder's access, and before this
        it did not.
        """
        self.token_version = (self.token_version or 0) + 1

    @property
    def is_pending_deletion(self) -> bool:
        return self.deletion_requested_at is not None

    @property
    def deletion_due_at(self):
        if not self.deletion_requested_at:
            return None
        from datetime import timedelta
        return self.deletion_requested_at + timedelta(hours=DELETION_GRACE_HOURS)

    def to_dict(self) -> dict:
        return {
            "id":                    self.id,
            "username":              self.username,
            "email":                 self.email,
            "timezone":              self.timezone or DEFAULT_TIMEZONE_NAME,
            "created_at":            iso_utc(self.created_at),
            "deletion_requested_at": iso_utc(self.deletion_requested_at),
            "deletion_due_at":       iso_utc(self.deletion_due_at),
        }

    def __repr__(self):
        return f"<User {self.username}>"


# ─── Income ───────────────────────────────────────────────────────────────────

class Income(db.Model):
    __tablename__ = "incomes"

    id          = db.Column(db.Integer, primary_key=True)
    user_id     = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    amount      = db.Column(db.Float, nullable=False)
    income_type = db.Column(db.String(50), nullable=False, default="monthly")
    description = db.Column(db.String(255), nullable=True)
    date_added  = db.Column(db.DateTime, default=utc_now, nullable=False)

    # The M-Pesa confirmation code (e.g. "SB27LJ9O3R"), when this row came from
    # an imported SMS. Unique per user so importing the same message twice is
    # refused by the database rather than silently double-counted. NULL for
    # anything entered by hand, and NULLs never collide with each other in
    # either SQLite or Postgres, so manual entries are unconstrained.
    mpesa_code  = db.Column(db.String(20), nullable=True)

    __table_args__ = (
        db.UniqueConstraint("user_id", "mpesa_code", name="uq_income_user_mpesa_code"),
    )

    def to_dict(self) -> dict:
        return {
            "id":          self.id,
            "user_id":     self.user_id,
            "amount":      self.amount,
            "income_type": self.income_type,
            "description": self.description,
            "date_added":  iso_utc(self.date_added),
            "mpesa_code":  self.mpesa_code,
        }

    def __repr__(self):
        return f"<Income {self.income_type} KES {self.amount}>"


# ─── Expense ──────────────────────────────────────────────────────────────────

class Expense(db.Model):
    __tablename__ = "expenses"

    id                  = db.Column(db.Integer, primary_key=True)
    user_id             = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    amount              = db.Column(db.Float, nullable=False)
    category            = db.Column(db.String(50), nullable=False)
    description         = db.Column(db.String(255), nullable=True)
    expense_type        = db.Column(db.String(20), nullable=False, default="daily")
    recurrence_interval = db.Column(db.String(20), nullable=True)
    date_added          = db.Column(db.DateTime, default=utc_now, nullable=False)

    # The M-Pesa confirmation code (e.g. "SB27LJ9O3R"), when this row came from
    # an imported SMS. Unique per user so importing the same message twice is
    # refused by the database rather than silently double-counted. NULL for
    # anything entered by hand, and NULLs never collide with each other in
    # either SQLite or Postgres, so manual entries are unconstrained.
    mpesa_code          = db.Column(db.String(20), nullable=True)

    __table_args__ = (
        db.UniqueConstraint("user_id", "mpesa_code", name="uq_expense_user_mpesa_code"),
    )

    def to_dict(self) -> dict:
        return {
            "id":                   self.id,
            "user_id":              self.user_id,
            "amount":               self.amount,
            "category":             self.category,
            "description":          self.description,
            "expense_type":         self.expense_type,
            "recurrence_interval":  self.recurrence_interval,
            "date_added":           iso_utc(self.date_added),
            "mpesa_code":           self.mpesa_code,
        }

    def __repr__(self):
        return f"<Expense {self.category} KES {self.amount}>"


# ─── Budget ───────────────────────────────────────────────────────────────────

class Budget(db.Model):
    __tablename__ = "budgets"

    id         = db.Column(db.Integer, primary_key=True)
    user_id    = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    category   = db.Column(db.String(50), nullable=False)
    limit      = db.Column(db.Float, nullable=False)
    month_year = db.Column(db.String(7), nullable=False)
    created_at = db.Column(db.DateTime, default=utc_now, nullable=False)

    __table_args__ = (
        db.UniqueConstraint("user_id", "category", "month_year", name="uq_user_category_month"),
    )

    def to_dict(self) -> dict:
        return {
            "id":         self.id,
            "user_id":    self.user_id,
            "category":   self.category,
            "limit":      self.limit,
            "month_year": self.month_year,
        }

    def __repr__(self):
        return f"<Budget {self.category} KES {self.limit} ({self.month_year})>"


# ─── SavingsGoal ──────────────────────────────────────────────────────────────

class SavingsGoal(db.Model):
    __tablename__ = "savings_goals"

    id          = db.Column(db.Integer, primary_key=True)
    user_id     = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    name        = db.Column(db.String(100), nullable=False)
    goal_amount = db.Column(db.Float, nullable=False)
    due_date    = db.Column(db.Date, nullable=False)
    date_set    = db.Column(db.DateTime, default=utc_now, nullable=False)
    is_active   = db.Column(db.Boolean, default=True, nullable=False)

    contributions = db.relationship(
        "GoalContribution", backref="goal", lazy=True, cascade="all, delete-orphan"
    )

    @property
    def total_contributed(self) -> float:
        return sum(c.amount for c in self.contributions)

    def to_dict(self) -> dict:
        return {
            "id":                self.id,
            "user_id":           self.user_id,
            "name":              self.name,
            "goal_amount":       self.goal_amount,
            "total_contributed": self.total_contributed,
            "due_date":          self.due_date.isoformat(),   # calendar date, no timezone
            "date_set":          iso_utc(self.date_set),
            "is_active":         self.is_active,
        }

    def __repr__(self):
        return f"<SavingsGoal {self.name} KES {self.goal_amount}>"


# ─── GoalContribution ─────────────────────────────────────────────────────────

class GoalContribution(db.Model):
    __tablename__ = "goal_contributions"

    id         = db.Column(db.Integer, primary_key=True)
    goal_id    = db.Column(db.Integer, db.ForeignKey("savings_goals.id"), nullable=False)
    user_id    = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    amount     = db.Column(db.Float, nullable=False)
    note       = db.Column(db.String(255), nullable=True)
    date_added = db.Column(db.DateTime, default=utc_now, nullable=False)

    def to_dict(self) -> dict:
        return {
            "id":         self.id,
            "goal_id":    self.goal_id,
            "user_id":    self.user_id,
            "amount":     self.amount,
            "note":       self.note,
            "date_added": iso_utc(self.date_added),
        }

    def __repr__(self):
        return f"<GoalContribution goal={self.goal_id} KES {self.amount}>"


# ─── UserCategory ─────────────────────────────────────────────────────────────

class UserCategory(db.Model):
    """Custom expense categories added by a student."""
    __tablename__ = "user_categories"

    id         = db.Column(db.Integer, primary_key=True)
    user_id    = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    name       = db.Column(db.String(50), nullable=False)
    created_at = db.Column(db.DateTime, default=utc_now, nullable=False)

    __table_args__ = (
        db.UniqueConstraint("user_id", "name", name="uq_user_category_name"),
    )

    def to_dict(self) -> dict:
        return {
            "id":         self.id,
            "name":       self.name,
            "created_at": iso_utc(self.created_at),
            "is_custom":  True,
        }

    def __repr__(self):
        return f"<UserCategory {self.name}>"


# ─── UserIncomeType ───────────────────────────────────────────────────────────

class UserIncomeType(db.Model):
    """
    Custom income types added by a student.
    Default income types (monthly, daily, helb, parental, gig, other)
    are hardcoded and never stored here.
    Users can add and delete their own custom income types freely.
    Names are unique per user — no duplicates allowed.
    """
    __tablename__ = "user_income_types"

    id         = db.Column(db.Integer, primary_key=True)
    user_id    = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    name       = db.Column(db.String(50), nullable=False)
    created_at = db.Column(db.DateTime, default=utc_now, nullable=False)

    __table_args__ = (
        db.UniqueConstraint("user_id", "name", name="uq_user_income_type_name"),
    )

    def to_dict(self) -> dict:
        return {
            "id":         self.id,
            "name":       self.name,
            "created_at": iso_utc(self.created_at),
            "is_custom":  True,
        }

    def __repr__(self):
        return f"<UserIncomeType {self.name}>"


# ─── Guardian ─────────────────────────────────────────────────────────────────

class Guardian(db.Model):
    __tablename__ = "guardians"

    id            = db.Column(db.Integer, primary_key=True)
    user_id       = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False, unique=True)
    phone_number  = db.Column(db.String(20), nullable=False)
    is_active     = db.Column(db.Boolean, default=True, nullable=False)
    last_notified = db.Column(db.DateTime, nullable=True)
    created_at    = db.Column(db.DateTime, default=utc_now, nullable=False)

    def to_dict(self) -> dict:
        return {
            "id":            self.id,
            "phone_number":  self.phone_number,
            "is_active":     self.is_active,
            "last_notified": iso_utc(self.last_notified),
            "created_at":    iso_utc(self.created_at),
        }

    def __repr__(self):
        return f"<Guardian {self.phone_number}>"


# ─── GuardianReport ───────────────────────────────────────────────────────────

class GuardianReport(db.Model):
    __tablename__ = "guardian_reports"

    id          = db.Column(db.Integer, primary_key=True)
    user_id     = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    report_text = db.Column(db.Text, nullable=False)
    score       = db.Column(db.Integer, nullable=False)
    trigger     = db.Column(db.String(10), nullable=False)
    created_at  = db.Column(db.DateTime, default=utc_now, nullable=False)

    def to_dict(self) -> dict:
        return {
            "id":          self.id,
            "report_text": self.report_text,
            "score":       self.score,
            "trigger":     self.trigger,
            "created_at":  iso_utc(self.created_at),
        }

    def __repr__(self):
        return f"<GuardianReport score={self.score} trigger={self.trigger}>"


# ─── HelbPlan ─────────────────────────────────────────────────────────────────

class HelbPlan(db.Model):
    __tablename__ = "helb_plans"

    id            = db.Column(db.Integer, primary_key=True)
    user_id       = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False, unique=True)
    semester_name = db.Column(db.String(100), nullable=False)
    helb_amount   = db.Column(db.Float, nullable=False)
    start_date    = db.Column(db.Date, nullable=False)
    end_date      = db.Column(db.Date, nullable=False)
    allocations   = db.Column(db.Text, nullable=False, default="{}")
    created_at    = db.Column(db.DateTime, default=utc_now, nullable=False)
    updated_at    = db.Column(db.DateTime, default=utc_now, onupdate=utc_now, nullable=False)

    def get_allocations(self) -> dict:
        try:
            return json.loads(self.allocations)
        except (json.JSONDecodeError, TypeError):
            return {}

    def set_allocations(self, allocations: dict):
        self.allocations = json.dumps(allocations)

    def to_dict(self) -> dict:
        return {
            "id":            self.id,
            "semester_name": self.semester_name,
            "helb_amount":   self.helb_amount,
            "start_date":    self.start_date.isoformat(),   # calendar date, no timezone
            "end_date":      self.end_date.isoformat(),     # calendar date, no timezone
            "allocations":   self.get_allocations(),
            "created_at":    iso_utc(self.created_at),
            "updated_at":    iso_utc(self.updated_at),
        }

    def __repr__(self):
        return f"<HelbPlan {self.semester_name} KES {self.helb_amount}>"