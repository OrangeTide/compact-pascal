#!/usr/bin/env node

/**
 * Simple Node.js server for testing the playground locally.
 * This wraps the native compiler to simulate a WASM-based compiler API.
 *
 * Usage:
 *   node compile-server.js
 *   Open browser to http://localhost:8080/playground/
 *
 * This is a development tool only. In production, the compiler
 * will be embedded as a WASM module.
 *
 * NOTE: The FPC-compiled native binary has issues when invoked as a
 * child process from Node.js (crashes with "Runtime error 6"). The
 * server currently attempts workarounds but they may not always work.
 * For now, the playground is primarily for demonstrating the architecture.
 * Once the compiler achieves self-hosting and produces a WASM snapshot,
 * this file will not be needed.
 */

const http = require('http');
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');
const url = require('url');

const PORT = 8080;
const COMPILER_BIN = path.join(__dirname, '../../compiler/cpas');
const PAGES_DIR = path.join(__dirname, '..');

// Serve static files and proxy compile requests
const server = http.createServer((req, res) => {
  const parsedUrl = url.parse(req.url, true);
  const pathname = parsedUrl.pathname;

  // Handle compile API
  if (pathname === '/api/compile') {
    if (req.method !== 'POST') {
      res.writeHead(405, { 'Content-Type': 'text/plain' });
      res.end('Method Not Allowed');
      return;
    }

    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      try {
        const input = JSON.parse(body).source;

        // Use temp file as a workaround for FPC binary issues
        const tmpFile = '/tmp/cpas-' + Date.now() + '.pas';
        fs.writeFileSync(tmpFile, input);

        const { execFile } = require('child_process');
        execFile('sh', ['-c', `"${COMPILER_BIN}" < "${tmpFile}"`],
          { maxBuffer: 10 * 1024 * 1024 },
          (error, stdout, stderr) => {
            fs.unlink(tmpFile, () => {});
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({
              wasm: Buffer.from(stdout).toString('base64'),
              stderr: stderr,
              success: !error && stdout.length > 0
            }));
          }
        );
      } catch (err) {
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: err.message }));
      }
    });
    return;
  }

  // Serve static files from pages/
  let filePath = path.join(PAGES_DIR, pathname);
  if (pathname === '/' || pathname === '/playground/') {
    filePath = path.join(PAGES_DIR, 'playground/index.html');
  }

  fs.stat(filePath, (err, stats) => {
    if (err) {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('Not Found');
      return;
    }

    if (stats.isDirectory()) {
      filePath = path.join(filePath, 'index.html');
    }

    const contentType = getContentType(filePath);
    res.writeHead(200, { 'Content-Type': contentType });
    fs.createReadStream(filePath).pipe(res);
  });
});

function getContentType(filePath) {
  const ext = path.extname(filePath);
  const types = {
    '.html': 'text/html',
    '.js': 'application/javascript',
    '.css': 'text/css',
    '.json': 'application/json',
    '.wasm': 'application/wasm',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.gif': 'image/gif',
    '.svg': 'image/svg+xml',
    '.pas': 'text/plain'
  };
  return types[ext] || 'application/octet-stream';
}

server.listen(PORT, () => {
  console.log(`Playground server running at http://localhost:${PORT}/playground/`);
  console.log(`Press Ctrl+C to stop`);
});
