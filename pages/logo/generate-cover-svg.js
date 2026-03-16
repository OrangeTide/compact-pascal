#!/usr/bin/env node
// Generates compact-pascal-cover.svg — the white paper cover image
// Usage: node generate-cover-svg.js > compact-pascal-cover.svg

const ROT_X = -53 * Math.PI / 180;
const ROT_Z = 74 * Math.PI / 180;
const COS_RX = Math.cos(ROT_X), SIN_RX = Math.sin(ROT_X);
const COS_RZ = Math.cos(ROT_Z), SIN_RZ = Math.sin(ROT_Z);
const FREQ = 2.0, AMP = 1.4;

const SIZE = 800;  // viewBox units
const CX = SIZE / 2, CY = SIZE * 0.47;
const SCALE = 320;
const GRID_N = 48;
const LINE_W = 0.8;

const SIENNA = '107,58,42';
const CREAM_TOP = 'rgb(245,240,224)';
const CREAM_BOT = 'rgb(235,228,210)';

function project(x, y, z) {
    let x1 = x * COS_RZ - y * SIN_RZ;
    let y1 = x * SIN_RZ + y * COS_RZ;
    let z1 = -z;
    let x2 = x1;
    let y2 = y1 * COS_RX - z1 * SIN_RX;
    let z2 = y1 * SIN_RX + z1 * COS_RX;
    return { x: CX + x2 * SCALE, y: CY + y2 * SCALE, depth: z2 };
}

function evalSurface(u, v) {
    let rr = Math.sqrt(u * u + v * v) * FREQ * 4;
    return Math.cos(rr) * Math.exp(-rr * 0.3) * AMP;
}

function r2(v) { return Math.round(v * 100) / 100; }

// Evaluate surface
let verts = [];
let zMin = Infinity, zMax = -Infinity;
for (let i = 0; i <= GRID_N; i++) {
    verts[i] = [];
    let u = -1 + (2 * i / GRID_N);
    for (let j = 0; j <= GRID_N; j++) {
        let v = -1 + (2 * j / GRID_N);
        let z = evalSurface(u, v);
        if (z < zMin) zMin = z;
        if (z > zMax) zMax = z;
        verts[i][j] = { x: u, y: v, z };
    }
}

let bzMin = Math.min(zMin, 0);
let bzMax = zMax * 1.05;
let zRange = bzMax - bzMin;
let zScale = zRange > 0 ? 1.5 / zRange : 1;

function toScreen(x, y, z) {
    let pz = (z - bzMin) * zScale - 0.75;
    return project(x, y, pz);
}

// Build SVG
let lines = [];

lines.push(`<?xml version="1.0" encoding="UTF-8"?>`);
lines.push(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${SIZE} ${SIZE}" width="${SIZE}" height="${SIZE}">`);

// Background gradient
lines.push(`  <defs>`);
lines.push(`    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">`);
lines.push(`      <stop offset="0%" stop-color="${CREAM_TOP}"/>`);
lines.push(`      <stop offset="100%" stop-color="${CREAM_BOT}"/>`);
lines.push(`    </linearGradient>`);
lines.push(`  </defs>`);
lines.push(`  <rect width="${SIZE}" height="${SIZE}" fill="url(#bg)"/>`);

// Bounding box
let corners = [
    toScreen(-1,-1,bzMin), toScreen(1,-1,bzMin),
    toScreen(1,1,bzMin), toScreen(-1,1,bzMin),
    toScreen(-1,-1,bzMax), toScreen(1,-1,bzMax),
    toScreen(1,1,bzMax), toScreen(-1,1,bzMax)
];
let boxEdges = [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]];
let depths = boxEdges.map(([a,b]) => (corners[a].depth + corners[b].depth)/2);
let sorted = [...depths].sort((a,b) => a-b);
let med = sorted[Math.floor(sorted.length/2)];

lines.push(`  <g id="bounding-box">`);
for (let ei = 0; ei < boxEdges.length; ei++) {
    let [a, b] = boxEdges[ei];
    let ca = corners[a], cb = corners[b];
    let isBack = depths[ei] < med;
    let opacity = isBack ? 0.3 : 0.55;
    let sw = isBack ? LINE_W * 0.5 : LINE_W * 0.7;
    let dash = isBack ? ` stroke-dasharray="${r2(6*LINE_W)} ${r2(5*LINE_W)}"` : '';
    lines.push(`    <line x1="${r2(ca.x)}" y1="${r2(ca.y)}" x2="${r2(cb.x)}" y2="${r2(cb.y)}" stroke="rgba(${SIENNA},${opacity})" stroke-width="${r2(sw)}"${dash}/>`);
}
lines.push(`  </g>`);

// Project surface points
let proj = [];
for (let i = 0; i <= GRID_N; i++) {
    proj[i] = [];
    for (let j = 0; j <= GRID_N; j++) {
        let p = verts[i][j];
        proj[i][j] = toScreen(p.x, p.y, p.z);
    }
}

// Collect and sort segments
let segments = [];
for (let i = 0; i <= GRID_N; i++) {
    for (let j = 0; j <= GRID_N; j++) {
        if (j < GRID_N) {
            let a = proj[i][j], b = proj[i][j+1];
            segments.push({ x1:a.x, y1:a.y, x2:b.x, y2:b.y, depth:(a.depth+b.depth)/2 });
        }
        if (i < GRID_N) {
            let a = proj[i][j], b = proj[i+1][j];
            segments.push({ x1:a.x, y1:a.y, x2:b.x, y2:b.y, depth:(a.depth+b.depth)/2 });
        }
    }
}
segments.sort((a,b) => a.depth - b.depth);

let sMin = segments[0].depth, sMax = segments[segments.length-1].depth;
let sRange = sMax - sMin || 1;

// Group segments by similar opacity to reduce SVG size
lines.push(`  <g id="surface" stroke-linecap="round">`);
for (let seg of segments) {
    let t = (seg.depth - sMin) / sRange;
    let alpha = r2(0.24 + 0.76 * t);
    let wt = r2(LINE_W * (0.4 + 0.6 * t));
    lines.push(`    <line x1="${r2(seg.x1)}" y1="${r2(seg.y1)}" x2="${r2(seg.x2)}" y2="${r2(seg.y2)}" stroke="rgba(${SIENNA},${alpha})" stroke-width="${wt}"/>`);
}
lines.push(`  </g>`);

lines.push(`</svg>`);

process.stdout.write(lines.join('\n') + '\n');
