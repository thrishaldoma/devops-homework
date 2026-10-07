# Multi-stage build for the calculator service.
# Stage 1 installs dependencies and runs the test suite, so an image is only
# ever produced from code that passes its tests.
FROM python:3.12-slim AS builder
WORKDIR /src
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt
COPY pytest.ini .
COPY app/ ./app/
COPY tests/ ./tests/
RUN PYTHONPATH=/install/lib/python3.12/site-packages python -m pytest -q

# Stage 2 is the runtime image: no tests, no pytest, no build tooling.
FROM python:3.12-slim
# Run as a non-root user - a container running as root is a container escape
# away from being host root.
RUN useradd --create-home --uid 10001 appuser
WORKDIR /app
COPY --from=builder /install /usr/local
COPY app/ ./app/
USER appuser
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
  CMD python -c "from app.calculator import add; assert add(1,1)==2" || exit 1
ENTRYPOINT ["python", "-m", "app.calculator"]
