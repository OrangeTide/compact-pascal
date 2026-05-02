/**
 * Made by a machine. PUBLIC DOMAIN (CC0-1.0)
 * Light's Out browser game host bridge
 * Canvas rendering, Web Audio, pointer events
 */

(function() {
  'use strict';

  // Virtual canvas size (pixels)
  const VIRT_WIDTH = 500;
  const VIRT_HEIGHT = 600;

  let canvas = null;
  let ctx = null;
  let wasmInstance = null;
  let scaleX = 1;
  let scaleY = 1;
  let audioContext = null;
  let animFrameHandle = null;
  let animStartTime = null;

  // Initialize the game
  function init() {
    canvas = document.getElementById('canvas');
    if (!canvas) {
      console.error('Canvas element not found');
      return;
    }

    ctx = canvas.getContext('2d');
    if (!ctx) {
      console.error('Failed to get 2D context');
      return;
    }

    // Set up canvas size (backing store for high-DPI)
    const rect = canvas.getBoundingClientRect();
    const dpr = window.devicePixelRatio || 1;
    canvas.width = VIRT_WIDTH * dpr;
    canvas.height = VIRT_HEIGHT * dpr;
    canvas.style.width = VIRT_WIDTH + 'px';
    canvas.style.height = VIRT_HEIGHT + 'px';

    // Calculate scale factors for pointer events
    scaleX = VIRT_WIDTH / rect.width;
    scaleY = VIRT_HEIGHT / rect.height;

    // Context scaling for high-DPI
    ctx.scale(dpr, dpr);

    // Set up pointer events
    canvas.addEventListener('pointerdown', handlePointerDown, false);
    canvas.style.touchAction = 'none';

    loadWasm();
  }

  // Load and instantiate the WASM module
  function loadWasm() {
    fetch('lightout.wasm')
      .then(response => {
        if (!response.ok) throw new Error('Failed to fetch lightout.wasm');
        return response.arrayBuffer();
      })
      .then(buffer => {
        const wasmImports = {
          host: {
            canvasClear: canvasClear,
            canvasFillRect: canvasFillRect,
            audioPlayTone: audioPlayTone,
            requestAnimFrame: requestAnimFrame,
            getTimeMs: getTimeMs
          }
        };

        const wasmModule = new WebAssembly.Module(buffer);
        wasmInstance = new WebAssembly.Instance(wasmModule, wasmImports);

        // Call Init to set up the game
        wasmInstance.exports.init();
      })
      .catch(err => {
        console.error('Failed to load WASM:', err);
        alert('Failed to load game');
      });
  }

  // ===== Host-provided functions (called from WASM) =====

  function canvasClear(r, g, b) {
    ctx.fillStyle = `rgb(${r}, ${g}, ${b})`;
    ctx.fillRect(0, 0, VIRT_WIDTH, VIRT_HEIGHT);
  }

  function canvasFillRect(x, y, w, h, r, g, b) {
    ctx.fillStyle = `rgb(${r}, ${g}, ${b})`;
    ctx.fillRect(x, y, w, h);
  }

  // Play a tone using Web Audio API
  function audioPlayTone(freqHz, durMs, offsetMs) {
    if (!audioContext) {
      audioContext = new (window.AudioContext || window.webkitAudioContext)();
    }

    // Ensure audio context is running (user gesture requirement)
    if (audioContext.state === 'suspended') {
      audioContext.resume();
    }

    const now = audioContext.currentTime;
    const startTime = now + (offsetMs / 1000);
    const duration = durMs / 1000;

    const osc = audioContext.createOscillator();
    const gain = audioContext.createGain();

    osc.connect(gain);
    gain.connect(audioContext.destination);

    osc.frequency.setValueAtTime(freqHz, startTime);
    gain.gain.setValueAtTime(0.3, startTime);
    gain.gain.exponentialRampToValueAtTime(0.01, startTime + duration);

    osc.start(startTime);
    osc.stop(startTime + duration);
  }

  // Request animation frame callback
  function requestAnimFrame() {
    if (animFrameHandle !== null) {
      return; // Already scheduled
    }

    animStartTime = getTimeMs();
    const scheduleFrame = () => {
      const elapsed = getTimeMs() - animStartTime;
      const continueAnim = wasmInstance.exports.stepAnimation(elapsed);

      if (continueAnim) {
        animFrameHandle = requestAnimationFrame(scheduleFrame);
      } else {
        animFrameHandle = null;
      }
    };

    animFrameHandle = requestAnimationFrame(scheduleFrame);
  }

  // Get time in milliseconds since init
  let startTime = Date.now();
  function getTimeMs() {
    return Date.now() - startTime;
  }

  // ===== Input handling =====

  function handlePointerDown(event) {
    if (!wasmInstance) return;

    event.preventDefault();

    // Get canvas bounding rect for event coordinate conversion
    const rect = canvas.getBoundingClientRect();

    // Convert event coordinates to virtual coordinates
    const clientX = event.clientX - rect.left;
    const clientY = event.clientY - rect.top;

    const virtX = Math.floor(clientX * scaleX);
    const virtY = Math.floor(clientY * scaleY);

    // Call the exported handler
    wasmInstance.exports.handleClick(virtX, virtY);
  }

  // Start the game when page loads
  window.addEventListener('DOMContentLoaded', init, false);
})();
