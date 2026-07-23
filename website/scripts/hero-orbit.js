// Orbit hero — a 3D orbit built with Three.js (core only).
// A central planet with six feature nodes revolving on tilted elliptical orbits.
// Nodes are camera-facing sprites: dark glass disc, thin colored rim, centered
// line icon — so the glyph is always crisp and perfectly centred.

import * as THREE from "three";

const canvas = document.getElementById("orbitScene");
const fallback = document.getElementById("heroFallback");
const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

function showFallbackOnly() {
  if (canvas) canvas.style.display = "none";
  if (fallback) fallback.style.opacity = "1";
}

/* ---- icon geometry, drawn in a 24×24 space (Lucide-style line icons) ---- */
const ICONS = {
  habits: (c) => {
    c.stroke(new Path2D("M8.5 14.5A2.5 2.5 0 0 0 11 12c0-1.38-.5-2-1-3-1.072-2.143-.224-4.054 2-6 .5 2.5 2 4.9 4 6.5 2 1.6 3 3.5 3 5.5a7 7 0 1 1-14 0c0-1.153.433-2.294 1-3a2.5 2.5 0 0 0 2.5 2.5"));
  },
  ideas: (c) => {
    c.stroke(new Path2D("M15 14c.2-1 .7-1.7 1.5-2.5 1-.9 1.5-2.2 1.5-3.5A6 6 0 0 0 6 8c0 1 .2 2.2 1.5 3.5.7.7 1.3 1.5 1.5 2.5"));
    c.stroke(new Path2D("M9 18h6"));
    c.stroke(new Path2D("M10 21h4"));
  },
  canvas: (c) => {
    const dot = (x, y) => { c.beginPath(); c.arc(x, y, 2.8, 0, Math.PI * 2); c.stroke(); };
    c.stroke(new Path2D("M8.6 13.5 15.4 17.5"));
    c.stroke(new Path2D("M15.4 6.5 8.6 10.5"));
    dot(18, 5); dot(6, 12); dot(18, 19);
  },
  tasks: (c) => {
    c.stroke(new Path2D("M21.8 11.1V12a9.8 9.8 0 1 1-5.8-8.9"));
    c.stroke(new Path2D("M21.5 4.5 12 14.1l-3-3"));
  },
  people: (c) => {
    c.stroke(new Path2D("M16 20.5v-1.8a3.8 3.8 0 0 0-3.8-3.8H6.4a3.8 3.8 0 0 0-3.8 3.8v1.8"));
    c.beginPath(); c.arc(9.3, 7.3, 3.8, 0, Math.PI * 2); c.stroke();
    c.stroke(new Path2D("M21.5 20.5v-1.8a3.8 3.8 0 0 0-2.9-3.7"));
    c.stroke(new Path2D("M15.8 3.7a3.8 3.8 0 0 1 0 7.3"));
  },
  command: (c) => {
    c.stroke(new Path2D("M18 3a3 3 0 0 0-3 3v12a3 3 0 0 0 3 3 3 3 0 0 0 3-3 3 3 0 0 0-3-3H6a3 3 0 0 0-3 3 3 3 0 0 0 3 3 3 3 0 0 0 3-3V6a3 3 0 0 0-3-3 3 3 0 0 0-3 3 3 3 0 0 0 3 3h12a3 3 0 0 0 3-3 3 3 0 0 0-3-3"));
  },
};

// Cohesive violet → blue → teal ramp (no rainbow).
const FEATURES = [
  // name,      color,     radiusX, radiusZ, inclination, speed, phase
  ["habits",  0x8B5CF6, 6.7, 3.2, 0.20, 0.26, 0.0],
  ["ideas",   0x6366F1, 7.5, 4.1, -0.28, 0.20, 1.15],
  ["canvas",  0x3D6DF2, 8.4, 5.0, 0.13, 0.16, 2.45],
  ["tasks",   0x0EA5E9, 7.0, 2.8, 0.38, 0.30, 3.35],
  ["people",  0x0EA5A8, 9.0, 5.6, -0.17, 0.13, 4.65],
  ["command", 0xB687FF, 7.9, 4.6, 0.28, 0.23, 5.45],
];

function hexRGB(hex) {
  const c = new THREE.Color(hex);
  return [Math.round(c.r * 255), Math.round(c.g * 255), Math.round(c.b * 255)];
}

function radialTexture(hex) {
  const s = 128, cv = document.createElement("canvas");
  cv.width = cv.height = s;
  const ctx = cv.getContext("2d");
  const [r, g, b] = hexRGB(hex);
  const grad = ctx.createRadialGradient(s / 2, s / 2, 0, s / 2, s / 2, s / 2);
  grad.addColorStop(0, `rgba(${r},${g},${b},0.85)`);
  grad.addColorStop(0.3, `rgba(${r},${g},${b},0.36)`);
  grad.addColorStop(1, `rgba(${r},${g},${b},0)`);
  ctx.fillStyle = grad;
  ctx.fillRect(0, 0, s, s);
  const t = new THREE.CanvasTexture(cv);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

/* A camera-facing node: dark glass disc + thin colored rim + centred line icon. */
function nodeTexture(name, hex) {
  const S = 256, cv = document.createElement("canvas");
  cv.width = cv.height = S;
  const ctx = cv.getContext("2d");
  const [r, g, b] = hexRGB(hex);
  const cx = S / 2, cy = S / 2, R = 98;

  // disc
  ctx.beginPath();
  ctx.arc(cx, cy, R, 0, Math.PI * 2);
  ctx.fillStyle = "rgba(13,12,17,0.94)";
  ctx.fill();

  // top highlight
  const hi = ctx.createLinearGradient(0, cy - R, 0, cy + R);
  hi.addColorStop(0, "rgba(255,255,255,0.13)");
  hi.addColorStop(0.55, "rgba(255,255,255,0)");
  ctx.save(); ctx.clip(); ctx.fillStyle = hi; ctx.fillRect(0, 0, S, S); ctx.restore();

  // rim
  ctx.beginPath();
  ctx.arc(cx, cy, R - 2, 0, Math.PI * 2);
  ctx.strokeStyle = `rgba(${r},${g},${b},1)`;
  ctx.lineWidth = 5;
  ctx.stroke();

  // subtle colored inner tint so the node reads as an object, not a hole
  const tint = ctx.createRadialGradient(cx, cy - R * 0.3, 0, cx, cy, R);
  tint.addColorStop(0, `rgba(${r},${g},${b},0.20)`);
  tint.addColorStop(1, `rgba(${r},${g},${b},0.05)`);
  ctx.save();
  ctx.beginPath(); ctx.arc(cx, cy, R - 3, 0, Math.PI * 2); ctx.clip();
  ctx.fillStyle = tint; ctx.fillRect(0, 0, S, S);
  ctx.restore();

  // icon — 24-unit space, centred
  const box = 104, scale = box / 24;
  ctx.save();
  ctx.translate(cx - box / 2, cy - box / 2);
  ctx.scale(scale, scale);
  ctx.strokeStyle = "rgba(255,255,255,0.96)";
  ctx.lineWidth = 1.75;
  ctx.lineCap = "round";
  ctx.lineJoin = "round";
  ctx.fillStyle = "transparent";
  (ICONS[name] || ICONS.habits)(ctx);
  ctx.restore();

  const t = new THREE.CanvasTexture(cv);
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 4;
  return t;
}

function init() {
  let renderer;
  try {
    renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true, powerPreference: "high-performance" });
  } catch (e) { showFallbackOnly(); return; }
  if (!renderer || !renderer.getContext()) { showFallbackOnly(); return; }

  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  renderer.setClearColor(0x000000, 0);

  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(46, 1, 0.1, 100);
  camera.position.set(0, 1.6, 13.5);
  camera.lookAt(0, 0, 0);

  const system = new THREE.Group();
  system.rotation.x = 0.42;
  system.position.y = 0.9; // lift so nodes clear the sub-headline
  scene.add(system);

  /* ---- central planet ---- */
  const planet = new THREE.Group();
  system.add(planet);

  planet.add(new THREE.Mesh(
    new THREE.SphereGeometry(0.95, 64, 64),
    new THREE.MeshStandardMaterial({
      color: 0x6d47d9, emissive: 0x2d1663, emissiveIntensity: 0.5,
      roughness: 0.42, metalness: 0.15,
    })
  ));

  const planetGlow = new THREE.Sprite(new THREE.SpriteMaterial({
    map: radialTexture(0x7c5cf0), transparent: true, blending: THREE.AdditiveBlending,
    depthWrite: false, opacity: 0.75,
  }));
  planetGlow.scale.setScalar(4.2);
  planet.add(planetGlow);

  const ringPts = new THREE.EllipseCurve(0, 0, 2.05, 1.2, 0, Math.PI * 2)
    .getPoints(140).map((p) => new THREE.Vector3(p.x, p.y, 0));
  const ring = new THREE.LineLoop(
    new THREE.BufferGeometry().setFromPoints(ringPts),
    new THREE.LineBasicMaterial({ color: 0xcbb4ff, transparent: true, opacity: 0.42 })
  );
  ring.rotation.x = Math.PI / 2.1;
  ring.rotation.z = -0.5;
  planet.add(ring);

  /* ---- lights ---- */
  scene.add(new THREE.AmbientLight(0x8f86c8, 0.65));
  const key = new THREE.PointLight(0xffffff, 1.3, 40); key.position.set(6, 8, 10); scene.add(key);
  const rim = new THREE.PointLight(0x20a8ad, 0.9, 40); rim.position.set(-8, -3, -6); scene.add(rim);

  /* ---- feature nodes ---- */
  const sats = [];
  for (const [name, color, rx, rz, incl, speed, phase] of FEATURES) {
    const g = new THREE.Group();

    const glow = new THREE.Sprite(new THREE.SpriteMaterial({
      map: radialTexture(color), transparent: true, blending: THREE.AdditiveBlending,
      depthWrite: false, opacity: 0.5,
    }));
    glow.scale.setScalar(2.6);
    g.add(glow);

    const node = new THREE.Sprite(new THREE.SpriteMaterial({
      map: nodeTexture(name, color), transparent: true, depthWrite: false,
    }));
    node.scale.setScalar(1.1);
    g.add(node);

    const pts = new THREE.EllipseCurve(0, 0, rx, rz, 0, Math.PI * 2)
      .getPoints(128).map((p) => new THREE.Vector3(p.x, 0, p.y));
    const path = new THREE.LineLoop(
      new THREE.BufferGeometry().setFromPoints(pts),
      new THREE.LineBasicMaterial({ color: 0x9aa4c4, transparent: true, opacity: 0.11 })
    );

    const holder = new THREE.Group();
    holder.rotation.x = incl;
    holder.add(path, g);
    system.add(holder);

    sats.push({ g, rx, rz, speed, phase, glow });
  }

  /* ---- starfield ---- */
  const starCount = window.innerWidth < 700 ? 240 : 560;
  const pos = new Float32Array(starCount * 3);
  for (let i = 0; i < starCount; i++) {
    const r = 22 + Math.random() * 26, th = Math.random() * Math.PI * 2, ph = Math.acos(2 * Math.random() - 1);
    pos[i * 3] = r * Math.sin(ph) * Math.cos(th);
    pos[i * 3 + 1] = r * Math.sin(ph) * Math.sin(th);
    pos[i * 3 + 2] = r * Math.cos(ph) - 6;
  }
  const starGeo = new THREE.BufferGeometry();
  starGeo.setAttribute("position", new THREE.BufferAttribute(pos, 3));
  const stars = new THREE.Points(starGeo, new THREE.PointsMaterial({
    color: 0xffffff, size: 0.055, transparent: true, opacity: 0.45, depthWrite: false,
  }));
  scene.add(stars);

  /* ---- sizing ---- */
  function resize() {
    const w = canvas.clientWidth || window.innerWidth;
    const h = canvas.clientHeight || window.innerHeight;
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    camera.position.z = w < 760 ? 17 : 13.5;
    camera.updateProjectionMatrix();
  }
  resize();
  window.addEventListener("resize", resize);

  /* ---- parallax ---- */
  let tx = 0, ty = 0, cx = 0, cy = 0;
  window.addEventListener("pointermove", (e) => {
    tx = e.clientX / window.innerWidth - 0.5;
    ty = e.clientY / window.innerHeight - 0.5;
  }, { passive: true });

  const clock = new THREE.Clock();
  const tmp = new THREE.Vector3();
  let rafId = null;

  function step() {
    const t = clock.getElapsedTime();
    for (const s of sats) {
      const a = t * s.speed + s.phase;
      s.g.position.set(Math.cos(a) * s.rx, 0, Math.sin(a) * s.rz);
      const wz = s.g.getWorldPosition(tmp).z;
      const k = THREE.MathUtils.clamp((wz + 7) / 14, 0.25, 1);
      s.glow.material.opacity = 0.22 + k * 0.4;
      s.g.scale.setScalar(0.78 + k * 0.42);
    }
    planet.rotation.y = t * 0.14;
    system.rotation.y = t * 0.045;
    stars.rotation.y = t * 0.01;

    cx += (tx - cx) * 0.05;
    cy += (ty - cy) * 0.05;
    system.rotation.z = cx * 0.22;
    system.rotation.x = 0.42 + cy * 0.2;
    camera.position.x = cx * 1.3;
    camera.lookAt(0, 0, 0);

    renderer.render(scene, camera);
    rafId = requestAnimationFrame(step);
  }

  if (reduceMotion) {
    for (const s of sats) s.g.position.set(Math.cos(s.phase) * s.rx, 0, Math.sin(s.phase) * s.rz);
    renderer.render(scene, camera);
  } else {
    rafId = requestAnimationFrame(step);
    const hero = document.querySelector(".hero");
    if (hero && "IntersectionObserver" in window) {
      new IntersectionObserver((entries) => {
        for (const en of entries) {
          if (en.isIntersecting && rafId === null) rafId = requestAnimationFrame(step);
          else if (!en.isIntersecting && rafId !== null) { cancelAnimationFrame(rafId); rafId = null; }
        }
      }, { threshold: 0.01 }).observe(hero);
    }
  }
}

try { init(); } catch (e) { showFallbackOnly(); }
