"""
Every timezone decision in the backend lives here.

The database stores naive datetimes that are always UTC. Users are in Kenya, so
anything that answers a *calendar* question — which month is this transaction
in, which day did this spending fall on, what is today — has to be asked in
local time, not UTC. Mixing the two is what made transactions logged between
00:00 and 03:00 EAT disappear from the current month.

Why a fixed offset rather than zoneinfo.ZoneInfo("Africa/Nairobi"):
Kenya is UTC+3 and has never observed daylight saving time, so a fixed offset is
exact rather than approximate, for every past and future date. It also needs no
tz database — `zoneinfo` has no data on Windows without the `tzdata` package,
and the python:3.9-slim image in the Dockerfile ships none either, so ZoneInfo
would raise at runtime in production.

If the app ever ships outside Kenya, APP_TIMEZONE is the one line to revisit
(and at that point the offset should come from the client per-request).
"""
from datetime import date, datetime, timedelta, timezone
from typing import Optional, Tuple

# Africa/Nairobi. No DST, historically or scheduled.
APP_TIMEZONE = timezone(timedelta(hours=3))

__all__ = [
    "APP_TIMEZONE",
    "utc_now",
    "to_app_tz",
    "app_now",
    "app_today",
    "month_range_utc",
    "local_date_of",
    "iso_utc",
]


def utc_now() -> datetime:
    """
    Current UTC time as a naive datetime, matching how the columns store it.

    Replaces datetime.utcnow(), which is deprecated from Python 3.12.
    """
    return datetime.now(timezone.utc).replace(tzinfo=None)


def to_app_tz(moment: datetime) -> datetime:
    """Interpret a stored (naive UTC) datetime in local time."""
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=timezone.utc)
    return moment.astimezone(APP_TIMEZONE)


def app_now() -> datetime:
    """Current local time, timezone-aware."""
    return datetime.now(APP_TIMEZONE)


def app_today() -> date:
    """Today's date in Nairobi, which is not always today's date in UTC."""
    return app_now().date()


def local_date_of(moment: datetime) -> date:
    """
    The local calendar day a stored timestamp falls on.

    Used to bucket spending per day: an expense at 23:00 EAT is stored as 20:00
    UTC the same day, but one at 01:00 EAT is stored as 22:00 UTC the *previous*
    day, and grouping on the raw UTC date would file it against the wrong day.
    """
    return to_app_tz(moment).date()


def month_range_utc(year: int, month: int) -> Tuple[datetime, datetime]:
    """
    The naive-UTC half-open bounds [start, end) of a local calendar month.

    month_range_utc(2026, 9) covers September in Nairobi, which in UTC runs from
    2026-08-31 21:00 to 2026-09-30 21:00. Half-open so a transaction landing
    exactly on a boundary belongs to precisely one month.
    """
    start_local = datetime(year, month, 1, tzinfo=APP_TIMEZONE)
    if month == 12:
        end_local = datetime(year + 1, 1, 1, tzinfo=APP_TIMEZONE)
    else:
        end_local = datetime(year, month + 1, 1, tzinfo=APP_TIMEZONE)
    return (
        start_local.astimezone(timezone.utc).replace(tzinfo=None),
        end_local.astimezone(timezone.utc).replace(tzinfo=None),
    )


def iso_utc(moment: Optional[datetime]) -> Optional[str]:
    """
    Serialize a stored timestamp with an explicit UTC marker.

    Without the trailing "Z" the client's DateTime.parse() treats the string as
    local time and applies no conversion, which is why every timestamp in the
    app displayed three hours early. Only for real timestamps — plain calendar
    dates (a goal due date, a semester start) carry no timezone and must keep
    using .isoformat().
    """
    if moment is None:
        return None
    if moment.tzinfo is not None:
        moment = moment.astimezone(timezone.utc).replace(tzinfo=None)
    return moment.isoformat() + "Z"
