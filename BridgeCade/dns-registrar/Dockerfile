FROM python:3.12-alpine

# Fix: Unbuffered output for logging
ENV PYTHONUNBUFFERED=1

RUN apk add --no-cache tini docker && \
    pip install docker --break-system-packages

WORKDIR /app
COPY registrar.py /app/registrar.py

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["python", "/app/registrar.py"]
