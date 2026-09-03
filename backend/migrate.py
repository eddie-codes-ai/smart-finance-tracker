"""
Deprecated. The schema is owned by Alembic now.

This used to call db.create_all(), which adds missing *tables* but never a
missing *column* — so any model change after the first deploy silently never
reached a database that already existed. Running it now would recreate the
schema behind Alembic's back and leave the two out of step.

Apply the migrations instead:

    cd backend
    set FLASK_APP=app:create_app          # Windows;  export … on Linux/macOS
    flask db upgrade

Other commands you'll want:

    flask db migrate -m "what changed"    # generate a revision from the models
    flask db current                      # which revision this database is on
    flask db history                      # the full chain
    flask db stamp head                   # mark an already-correct database as
                                          # up to date WITHOUT running anything
"""
import sys

MESSAGE = __doc__


if __name__ == "__main__":
    print(MESSAGE)
    sys.exit(1)
