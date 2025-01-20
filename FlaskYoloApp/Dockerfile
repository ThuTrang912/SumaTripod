# Dockerfile for api_simple
FROM python:3.10

EXPOSE 5000

WORKDIR /app
COPY ./requirements.txt /app
RUN pip install -r requirements.txt

CMD ["python", "app.py"]
