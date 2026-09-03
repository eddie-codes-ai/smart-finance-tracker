"""
READ-ONLY audit for timestamps that may have been stored in the wrong frame.

Between the C-1 commit (the transaction date picker) and the C-2 commit (this
timezone fix), the app sent hand-picked dates as naive *local* text while the
server read every incoming timestamp as UTC. Any transaction whose date was
edited by hand in that window therefore sits 3 hours later than intended.

Records created normally are unaffected: they were always stamped with a real
UTC instant and were only ever *displayed* wrong.

This script only reads. It writes nothing and changes nothing. It prints the
transactions worth a look so you can decide whether any need correcting.

    cd backend
    venv/Scripts/python tests/audit_timestamps.py           # Windows
    venv/bin/python tests/audit_timestamps.py               # Linux/macOS

To point it at production instead of the local database:

    DATABASE_URL="<railway postgres url>" venv/bin/python tests/audit_timestamps.py
"""
import os
import sys

BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, BACKEND_DIR)

from sqlalchemy.exc import OperationalError, ProgrammingError   # noqa: E402

from app import create_app                                  # noqa: E402
from app_time import APP_TIMEZONE, to_app_tz                # noqa: E402
from models import Expense, Income                          # noqa: E402

# A hand-edited date arrives with the time-of-day copied from the original
# record, so it is not reliably identifiable on its own. What IS suspicious is
# a timestamp whose local reading lands in the small hours - the window where a
# 3-hour error is most likely to have moved the transaction across a day, and
# the window the whole bug was about.
SUSPICIOUS_LOCAL_HOURS = range(0, 3)   # 00:00-02:59 local


def rows_for(model, label):
    found = []
    for record in model.query.order_by(model.date_added).all():
        local = to_app_tz(record.date_added)
        if local.hour in SUSPICIOUS_LOCAL_HOURS:
            found.append((label, record, local))
    return found


def main():
    app = create_app()
    with app.app_context():
        print("Database : %s" % app.config["SQLALCHEMY_DATABASE_URI"].split("@")[-1][:60])
        print("Local tz : %s (Africa/Nairobi)" % APP_TIMEZONE.tzname(None))
        print()

        try:
            print("Scanned  : %d expenses, %d income rows"
                  % (Expense.query.count(), Income.query.count()))
            print()
            flagged = rows_for(Expense, "expense") + rows_for(Income, "income")
        except (OperationalError, ProgrammingError) as e:
            print("Could not read the transaction tables:")
            print("  %s" % str(e.orig).strip())
            print()
            print("This database is on an older schema than the models expect.")
            print("db.create_all() adds missing tables but never missing columns,")
            print("so a database created before a model changed stays behind -")
            print("the reason this project needs migrations (audit finding M-7).")
            print()
            print("Nothing was changed. Point DATABASE_URL at the database you")
            print("actually want to audit, or recreate this one from scratch.")
            return 1

        if not flagged:
            print("Nothing to review.")
            print()
            print("No transaction falls in the 00:00-02:59 local window, so none")
            print("of them can have been moved across a day boundary by the")
            print("date picker. Every timestamp will simply display 3 hours")
            print("later than before, which is the correction.")
            return 0

        print("%d transaction(s) sit between 00:00 and 02:59 local time." % len(flagged))
        print("These are worth eyeballing - if any had its date set by hand in")
        print("the app since the C-1 commit, its stored time is 3 hours late.")
        print()
        print("  %-8s %-6s %-21s %-21s %s" % (
            "kind", "id", "stored (UTC)", "shows as (local)", "description"))
        print("  " + "-" * 92)
        for label, record, local in sorted(flagged, key=lambda r: r[1].date_added):
            print("  %-8s %-6s %-21s %-21s %s" % (
                label,
                record.id,
                record.date_added.strftime("%Y-%m-%d %H:%M:%S"),
                local.strftime("%Y-%m-%d %H:%M:%S"),
                (record.description or "")[:34],
            ))
        print()
        print("Nothing was changed. To correct one, edit its date in the app -")
        print("the picker now sends UTC properly.")
        return 0


if __name__ == "__main__":
    sys.exit(main())
