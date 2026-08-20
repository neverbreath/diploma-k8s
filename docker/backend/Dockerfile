FROM python:3.10-alpine
WORKDIR /app
RUN adduser -D myuser
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
USER myuser
EXPOSE 5000
CMD ["python", "app.py"]
