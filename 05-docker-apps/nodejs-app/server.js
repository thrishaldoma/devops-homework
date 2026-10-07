const express = require("express");
const os = require("os");
const app = express();
const PORT = process.env.PORT || 3000;

app.get("/", (req, res) => {
  res.send(`
    <html><head><title>Node.js + Docker</title></head>
    <body style="font-family:sans-serif;text-align:center;padding-top:60px">
      <h1>Hello World from Node.js + Docker!</h1>
      <p>Container hostname: ${os.hostname()}</p>
      <p>Node version: ${process.version}</p>
    </body></html>
  `);
});

app.get("/health", (req, res) => res.json({ status: "ok" }));

app.listen(PORT, "0.0.0.0", () =>
  console.log(`Node.js server running on port ${PORT}`));
