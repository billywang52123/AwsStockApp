FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000

# Run the seeding script on container start, then run the uvicorn web server
CMD ["sh", "-c", "python scripts/seed_demo_data.py && uvicorn app.main:app --host 0.0.0.0 --port 8000"]
