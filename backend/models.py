import json
from datetime import datetime
from flask_sqlalchemy import SQLAlchemy
from werkzeug.security import generate_password_hash, check_password_hash

db = SQLAlchemy()

# ─── Constants ────────────────────────────────────────────────────────────────

INCOME_TYPES        = ('monthly', 'daily', 'helb', 'parental', 'gig', 'other')
EXPENSE_TYPES       = ('daily', 'monthly', 'one-time', 'recurring')
RECURRENCE_CHOICES  = ('daily', 'weekly', 'biweekly', 'monthly')
EXPENSE_CATEGORIES  = (
    'Food', 'Transport', 'Entertainment', 'Shopping',
    'Health', 'Education', 'Utilities', 'Rent', 'Other'
)
TRIGGER_CHOICES     = ('auto', 'manual')


# ─── User ─────────────────────────────────────────────────────────────────────

class User(db.Model):
    __tablename__ = "users"

    id                 = db.Column(db.Integer,     primary_key=True)
    username           = db.Column(db.String(80),  unique=True,  nullable=False)
    password_hash      = db.Column(db.String(256),               nullable=False)
    email              = db.Column(db.String(120),  unique=True,  nullable=True)
    google_id          = db.Column(db.String(100),  unique=True,  nullable=True)
    reset_token        = db.Column(db.String(10),                 nullable=True)
    reset_token_expiry = db.Column(db.DateTime,                   nullable=True)
    created_at         = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)

    incomes          = db.relationship("Income",         backref="owner", lazy=True, cascade="all, delete-orphan")
    expenses         = db.relationship("Expense",        backref="owner", lazy=True, cascade="all, delete-orphan")
    budgets          = db.relationship("Budget",         backref="owner", lazy=True, cascade="all, delete-orphan")
    savings_goals    = db.relationship("SavingsGoal",    backref="owner", lazy=True, cascade="all, delete-orphan")
    guardian         = db.relationship("Guardian",       backref="user",  uselist=False, cascade="all, delete-orphan")
    guardian_reports = db.relationship("GuardianReport", backref="user",  lazy=True, cascade="all, delete-orphan")
    helb_plan        = db.relationship("HelbPlan",       backref="user",  uselist=False, cascade="all, delete-orphan")

    def set_password(self, password: str):
        self.password_hash = generate_password_hash(password)

    def check_password(self, password: str) -> bool:
        return check_password_hash(self.password_hash, password)

    def to_dict(self) -> dict:
        return {
            "id":         self.id,
            "username":   self.username,
            "email":      self.email,
            "created_at": self.created_at.isoformat(),
        }

    def __repr__(self):
        return f"<User {self.username}>"


# ─── Income ───────────────────────────────────────────────────────────────────

class Income(db.Model):
    __tablename__ = "incomes"

    id          = db.Column(db.Integer, primary_key=True)
    user_id     = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    amount      = db.Column(db.Float, nullable=False)
    income_type = db.Column(db.String(20), nullable=False, default="monthly")
    description = db.Column(db.String(255), nullable=True)
    date_added  = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)

    def to_dict(self) -> dict:
        return {
            "id":          self.id,
            "amount":      self.amount,
            "income_type": self.income_type,
            "description": self.description,
            "date_added":  self.date_added.isoformat(),
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
    date_added          = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)

    def to_dict(self) -> dict:
        return {
            "id":                   self.id,
            "amount":               self.amount,
            "category":             self.category,
            "description":          self.description,
            "expense_type":         self.expense_type,
            "recurrence_interval":  self.recurrence_interval,
            "date_added":           self.date_added.isoformat(),
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
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)

    __table_args__ = (
        db.UniqueConstraint("user_id", "category", "month_year", name="uq_user_category_month"),
    )

    def to_dict(self) -> dict:
        return {
            "id":         self.id,
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
    date_set    = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)
    is_active   = db.Column(db.Boolean, default=True, nullable=False)

    def to_dict(self) -> dict:
        return {
            "id":          self.id,
            "name":        self.name,
            "goal_amount": self.goal_amount,
            "due_date":    self.due_date.isoformat(),
            "date_set":    self.date_set.isoformat(),
            "is_active":   self.is_active,
        }

    def __repr__(self):
        return f"<SavingsGoal {self.name} KES {self.goal_amount}>"


# ─── Guardian ─────────────────────────────────────────────────────────────────

class Guardian(db.Model):
    __tablename__ = "guardians"

    id            = db.Column(db.Integer, primary_key=True)
    user_id       = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False, unique=True)
    phone_number  = db.Column(db.String(20), nullable=False)
    is_active     = db.Column(db.Boolean, default=True, nullable=False)
    last_notified = db.Column(db.DateTime, nullable=True)
    created_at    = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)

    def to_dict(self) -> dict:
        return {
            "id":            self.id,
            "phone_number":  self.phone_number,
            "is_active":     self.is_active,
            "last_notified": self.last_notified.isoformat() if self.last_notified else None,
            "created_at":    self.created_at.isoformat(),
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
    created_at  = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)

    def to_dict(self) -> dict:
        return {
            "id":          self.id,
            "report_text": self.report_text,
            "score":       self.score,
            "trigger":     self.trigger,
            "created_at":  self.created_at.isoformat(),
        }

    def __repr__(self):
        return f"<GuardianReport score={self.score} trigger={self.trigger}>"


# ─── HelbPlan ─────────────────────────────────────────────────────────────────

class HelbPlan(db.Model):
    """
    Stores the student's HELB semester budget plan.
    One plan per student (uselist=False). Saving a new plan overwrites the old one.
    Allocations are stored as JSON text — a dict of {category: amount}.
    """
    __tablename__ = "helb_plans"

    id            = db.Column(db.Integer, primary_key=True)
    user_id       = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False, unique=True)
    semester_name = db.Column(db.String(100), nullable=False)
    helb_amount   = db.Column(db.Float, nullable=False)
    start_date    = db.Column(db.Date, nullable=False)
    end_date      = db.Column(db.Date, nullable=False)
    allocations   = db.Column(db.Text, nullable=False, default="{}")  # JSON string
    created_at    = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)
    updated_at    = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    def get_allocations(self) -> dict:
        """Deserialize allocations from JSON string to dict."""
        try:
            return json.loads(self.allocations)
        except (json.JSONDecodeError, TypeError):
            return {}

    def set_allocations(self, allocations: dict):
        """Serialize allocations dict to JSON string."""
        self.allocations = json.dumps(allocations)

    def to_dict(self) -> dict:
        return {
            "id":            self.id,
            "semester_name": self.semester_name,
            "helb_amount":   self.helb_amount,
            "start_date":    self.start_date.isoformat(),
            "end_date":      self.end_date.isoformat(),
            "allocations":   self.get_allocations(),
            "created_at":    self.created_at.isoformat(),
            "updated_at":    self.updated_at.isoformat(),
        }

    def __repr__(self):
        return f"<HelbPlan {self.semester_name} KES {self.helb_amount}>"