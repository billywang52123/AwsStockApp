FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000

# Entrypoint: optional idempotent seed (SEED_ON_START=true), then run uvicorn
RUN chmod +x scripts/entrypoint.sh
CMD ["sh", "scripts/entrypoint.sh"]
