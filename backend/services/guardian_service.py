import re
from datetime import timedelta
from typing import Optional

from app_time import utc_now
from models import db, Guardian, GuardianReport


COOLDOWN_HOURS = 24


def get_guardian(user_id: int):
    """Return the active guardian for a user, or None."""
    return Guardian.query.filter_by(user_id=user_id, is_active=True).first()


def normalise_phone(raw: str) -> Optional[str]:
    """
    Validate and normalise a guardian's phone number to E.164, or None.

    Nothing checked this before, so any string was stored: "_format_e164" would
    turn "hello" into "+hello" and the problem only surfaced later, as an alert
    that silently failed to send at the moment it was needed.

    Kenyan local format (07xx / 01xx) is normalised to +254, matching what the
    notification service does when it dials.
    """
    if not isinstance(raw, str):
        return None

    cleaned = re.sub(r"[\s()\-.]", "", raw.strip())
    if not cleaned:
        return None

    if cleaned.startswith("+"):
        digits, prefix = cleaned[1:], "+"
    elif cleaned.startswith("0"):
        # 0712345678 -> +254712345678. The local part has to be checked before
        # the country code goes on, or a far-too-short number like "071234"
        # becomes "25471234" and clears the general length check below.
        if not (len(cleaned) == 10 and cleaned[1:].isdigit()):
            return None
        digits, prefix = "254" + cleaned[1:], "+"
    else:
        digits, prefix = cleaned, "+"

    if not digits.isdigit():
        return None
    # E.164 allows up to 15 digits; a country code plus a subscriber number is
    # never shorter than about 8.
    if not (8 <= len(digits) <= 15):
        return None

    return prefix + digits


def link_guardian(user_id: int, phone_number: str) -> Guardian:
    """
    Link a guardian to a student account.
    If one already exists, update the phone number and re-activate.

    Expects an already-normalised number; the route validates before calling.
    """
    guardian = Guardian.query.filter_by(user_id=user_id).first()
    if guardian:
        guardian.phone_number = phone_number
        guardian.is_active    = True
    else:
        guardian = Guardian(user_id=user_id, phone_number=phone_number)
        db.session.add(guardian)
    db.session.commit()
    return guardian


def unlink_guardian(user_id: int) -> bool:
    """Soft-deactivate the guardian link. Returns True if found, False if not."""
    guardian = Guardian.query.filter_by(user_id=user_id).first()
    if not guardian:
        return False
    guardian.is_active = False
    db.session.commit()
    return True


def can_auto_notify(guardian: Guardian) -> bool:
    """
    Check if the 24-hour cooldown has passed since last auto-notification.
    Always returns True if the guardian has never been notified.
    """
    if guardian.last_notified is None:
        return True
    return (utc_now() - guardian.last_notified) >= timedelta(hours=COOLDOWN_HOURS)


def build_guardian_report(username: str, analysis_result: dict, payload: dict) -> str:
    """
    Generate the WhatsApp/SMS message text to send to the guardian.
    Plain text, concise enough for SMS.
    """
    score       = analysis_result.get("score", 0)
    category    = analysis_result.get("category", "Unknown")
    persona     = analysis_result.get("persona", "")
    savings     = payload.get("savings", 0)
    income      = payload.get("income", 0)
    expenses    = payload.get("expenses", 0)
    # No datetime fallback here: "today" is a per-user, timezone-dependent
    # question this module cannot answer, and the payload always carries the
    # value computed in the user's own zone. (This previously called
    # datetime.now() against an import that had been removed, so the fallback
    # path raised NameError rather than defaulting.)
    day         = payload.get("day_of_month", "-")
    goal_health = payload.get("goal_health", "")
    period      = payload.get("period", "")

    top_advice  = analysis_result.get("advice", [])[:2]
    advice_text = "\n".join(f"  - {a}" for a in top_advice) if top_advice else "  - No specific alerts."

    report = (
        f"Smart Finance Tracker - Update for {username}\n"
        f"Period: {period} | Day {day} of the month\n"
        f"{'─' * 38}\n"
        f"Financial Score : {score}/100 ({category})\n"
        f"Profile         : {persona}\n\n"
        f"Income   : KES {income:,.2f}\n"
        f"Expenses : KES {expenses:,.2f}\n"
        f"Savings  : KES {savings:,.2f}\n\n"
        f"Goal Status: {goal_health}\n\n"
        f"Key Alerts:\n{advice_text}\n"
    )
    return report


def save_report(user_id: int, report_text: str, score: int, trigger: str) -> GuardianReport:
    """
    Persist a guardian report and update last_notified on the guardian.
    trigger: 'auto' | 'manual'
    """
    report = GuardianReport(
        user_id     = user_id,
        report_text = report_text,
        score       = score,
        trigger     = trigger,
    )
    db.session.add(report)

    guardian = Guardian.query.filter_by(user_id=user_id, is_active=True).first()
    if guardian:
        guardian.last_notified = utc_now()

    db.session.commit()
    return report


def get_latest_report(user_id: int):
    """Return the most recently saved guardian report for a user."""
    return (
        GuardianReport.query
        .filter_by(user_id=user_id)
        .order_by(GuardianReport.created_at.desc())
        .first()
    )