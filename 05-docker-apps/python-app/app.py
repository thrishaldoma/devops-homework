from flask import Flask
import socket, sys

app = Flask(__name__)


@app.route("/")
def hello():
    return f"""
    <html><head><title>Python + Docker</title></head>
    <body style="font-family:sans-serif;text-align:center;padding-top:60px">
      <h1>Hello World from Python + Docker!</h1>
      <p>Container hostname: {socket.gethostname()}</p>
      <p>Python version: {sys.version.split()[0]}</p>
    </body></html>
    """


@app.route("/health")
def health():
    return {"status": "ok"}


if __name__ == "__main__":
    # 0.0.0.0 is essential: 127.0.0.1 would only be
    # reachable from inside the container
    app.run(host="0.0.0.0", port=5000)
