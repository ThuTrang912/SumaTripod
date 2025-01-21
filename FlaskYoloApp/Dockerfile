# Dockerfile for api_simple
FROM python:3.10

# Cai ??t th? vi?n c?n thi?t cho OpenCV
RUN apt-get update && apt-get install -y \
    libgl1 \
    && rm -rf /var/lib/apt/lists/*

EXPOSE 5000

WORKDIR /app
COPY ./requirements.txt /app
RUN pip install -r requirements.txt

CMD ["python", "app.py"]
