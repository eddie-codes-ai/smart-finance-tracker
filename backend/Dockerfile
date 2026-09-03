FROM python:3.9-slim

RUN apt-get update && apt-get install -y libpq-dev gcc && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

ENV FLASK_APP=app:create_app

# Apply migrations before serving: the schema is owned by Alembic now, not by
# db.create_all(). Bind explicitly too — gunicorn otherwise defaults to
# 127.0.0.1:8000, ignoring the $PORT the platform assigns, which leaves the
# container unreachable from outside.
CMD flask db upgrade && gunicorn --bind "0.0.0.0:${PORT:-5000}" "app:create_app()"