# Hardened image for the DevSecOps demo.
#
# The course's reference Dockerfile (kept at ../reference/Dockerfile-course-reference)
# has three issues this one fixes, each of which a scanner or reviewer will flag:
#   1. runs as root            -> a container escape becomes host root
#   2. `python app/app.py`     -> Flask's dev server with debug=True, which exposes
#                                 the Werkzeug debugger (remote code execution)
#   3. unpinned base image     -> irreproducible builds
FROM python:3.12-slim AS builder
WORKDIR /src
COPY requirements.txt requirements-dev.txt ./
RUN pip install --no-cache-dir --prefix=/install -r requirements-dev.txt
COPY pytest.ini .
COPY app/ ./app/
COPY tests/ ./tests/
# Tests run inside the build: no image exists unless they pass.
RUN PYTHONPATH=/install/lib/python3.12/site-packages python -m pytest -q

FROM python:3.12-slim
# 1. non-root
RUN useradd --create-home --uid 10001 appuser
WORKDIR /app
# runtime deps only - no pytest, no coverage, no build tooling
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt gunicorn==23.0.0 \
 && rm -rf /root/.cache
COPY app/ ./app/
USER appuser
EXPOSE 5001
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
  CMD python -c "import urllib.request;urllib.request.urlopen('http://127.0.0.1:5001/health').read()" || exit 1
# 2. gunicorn, not the Flask dev server; debug is never enabled in the image
CMD ["gunicorn", "--bind", "0.0.0.0:5001", "--workers", "2", "app.app:app"]
