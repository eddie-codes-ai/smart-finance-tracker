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
    """Student account. Central FK for all other tables."""
    __tablename__ = "users"

    id            = db.Column(db.Integer, primary_key=True)
    username      = db.Column(db.String(80), unique=True, nullable=False)
    password_hash = db.Column(db.String(256), nullable=False)
    created_at    = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)

    # Relationships
    incomes          = db.relationship("Income",         backref="owner", lazy=True, cascade="all, delete-orphan")
    expenses         = db.relationship("Expense",        backref="owner", lazy=True, cascade="all, delete-orphan")
    budgets          = db.relationship("Budget",         backref="owner", lazy=True, cascade="all, delete-orphan")
    savings_goals    = db.relationship("SavingsGoal",    backref="owner", lazy=True, cascade="all, delete-orphan")
    guardian         = db.relationship("Guardian",       backref="user",  uselist=False, cascade="all, delete-orphan")
    guardian_reports = db.relationship("GuardianReport", backref="user",  lazy=True, cascade="all, delete-orphan")

    def set_password(self, password: str):
        self.password_hash = generate_password_hash(password)

    def check_password(self, password: str) -> bool:
        return check_password_hash(self.password_hash, password)

    def to_dict(self) -> dict:
        return {
            "id":         self.id,
            "username":   self.username,
            "created_at": self.created_at.isoformat(),
        }

    def __repr__(self):
        return f"<User {self.username}>"


# ─── Income ───────────────────────────────────────────────────────────────────

class Income(db.Model):
    """
    Every income record logged by the student.
    income_type captures the Kenyan student context:
    HELB disbursements, parental stipends, gig earnings, etc.
    """
    __tablename__ = "incomes"

    id          = db.Column(db.Integer, primary_key=True)
    user_id     = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    amount      = db.Column(db.Float, nullable=False)
    income_type = db.Column(db.String(20), nullable=False, default="monthly")  # from INCOME_TYPES
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
    """
    Every expense record logged by the student.
    expense_type distinguishes daily spending from one-off
    purchases and recurring bills — critical for accurate
    daily budget calculations and overspent day detection.
    """
    __tablename__ = "expenses"

    id                  = db.Column(db.Integer, primary_key=True)
    user_id             = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    amount              = db.Column(db.Float, nullable=False)
    category            = db.Column(db.String(50), nullable=False)       # from EXPENSE_CATEGORIES
    description         = db.Column(db.String(255), nullable=True)
    expense_type        = db.Column(db.String(20), nullable=False, default="daily")  # from EXPENSE_TYPES
    recurrence_interval = db.Column(db.String(20), nullable=True)        # from RECURRENCE_CHOICES, only if recurring
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
    """
    Spending limit per category per month per user.
    month_year format: 'YYYY-MM' e.g. '2025-07'
    Unique constraint prevents duplicate budgets for the
    same category in the same month.
    """
    __tablename__ = "budgets"

    id         = db.Column(db.Integer, primary_key=True)
    user_id    = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    category   = db.Column(db.String(50), nullable=False)
    limit      = db.Column(db.Float, nullable=False)
    month_year = db.Column(db.String(7), nullable=False)  # 'YYYY-MM'
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
    """
    A student's savings target.
    Multiple goals supported (e.g. laptop + rent deposit).
    is_active allows soft-closing a completed goal without
    losing it from history.
    """
    __tablename__ = "savings_goals"

    id          = db.Column(db.Integer, primary_key=True)
    user_id     = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    name        = db.Column(db.String(100), nullable=False)   # e.g. "Rent", "Laptop"
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
    """
    Guardian linked to a student account.
    One guardian per student (uselist=False on User relationship).
    is_active allows unlinking without losing notification history.
    last_notified drives the 24-hour auto-notify cooldown.
    """
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
    """
    Full history of every message sent to a guardian.
    Stores the exact text sent, the student's score at that
    point in time, and whether it was auto or manually triggered.
    """
    __tablename__ = "guardian_reports"

    id          = db.Column(db.Integer, primary_key=True)
    user_id     = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    report_text = db.Column(db.Text, nullable=False)
    score       = db.Column(db.Integer, nullable=False)
    trigger     = db.Column(db.String(10), nullable=False)  # 'auto' | 'manual'
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