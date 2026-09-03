FROM python:3.9-slim

RUN apt-get update && apt-get install -y libpq-dev gcc && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Bind explicitly: gunicorn defaults to 127.0.0.1:8000, which ignores the
# $PORT the platform assigns and is unreachable from outside the container.
CMD gunicorn --bind "0.0.0.0:${PORT:-5000}" "app:create_app()"