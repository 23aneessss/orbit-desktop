// Orbit hero — an orderly 3D orbital system (Three.js core only).
//
// Design rules that keep it reading as *designed* rather than random:
//   · every orbit is circular and COPLANAR — the whole system is tilted once
//   · radii are evenly spaced
//   · angular speed falls off with radius (Keplerian), so nothing looks arbitrary
//   · nodes are camera-facing sprites — graphite disc, ivory rim, centred line icon,
//     echoing the app icon exactly

import * as THREE from "three";

const canvas = document.getElementById("orbitScene");
const fallback = document.getElementById("heroFallback");
const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

const IVORY = "241,239,235";     // #F1EFEB — same warm ivory as the icon
const GRAPHITE = "26,24,30";

function showFallbackOnly() {
  if (canvas) canvas.style.display = "none";
  if (fallback) fallback.style.opacity = "1";
}

/* ---- line icons, drawn in a 24×24 space ---- */
const ICONS = {
  habits: (c) => {
    c.stroke(new Path2D("M8.5 14.5A2.5 2.5 0 0 0 11 12c0-1.38-.5-2-1-3-1.072-2.143-.224-4.054 2-6 .5 2.5 2 4.9 4 6.5 2 1.6 3 3.5 3 5.5a7 7 0 1 1-14 0c0-1.153.433-2.294 1-3a2.5 2.5 0 0 0 2.5 2.5"));
  },
  ideas: (c) => {
    c.stroke(new Path2D("M15 14c.2-1 .7-1.7 1.5-2.5 1-.9 1.5-2.2 1.5-3.5A6 6 0 0 0 6 8c0 1 .2 2.2 1.5 3.5.7.7 1.3 1.5 1.5 2.5"));
    c.stroke(new Path2D("M9 18h6")); c.stroke(new Path2D("M10 21h4"));
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

// Evenly spaced radii; tint is used only for a soft glow, never for the rim.
const R0 = 2.35, STEP = 0.63, K = 1.45;
const FEATURES = [
  ["habits",  0x8B5CF6],
  ["ideas",   0x6366F1],
  ["canvas",  0x3D6DF2],
  ["tasks",   0x0EA5E9],
  ["people",  0x0EA5A8],
  ["command", 0xB687FF],
];

function radialTexture(hex) {
  const s = 128, cv = document.createElement("canvas");
  cv.width = cv.height = s;
  const ctx = cv.getContext("2d");
  const c = new THREE.Color(hex);
  const r = Math.round(c.r * 255), g = Math.round(c.g * 255), b = Math.round(c.b * 255);
  const grad = ctx.createRadialGradient(s / 2, s / 2, 0, s / 2, s / 2, s / 2);
  grad.addColorStop(0, `rgba(${r},${g},${b},0.8)`);
  grad.addColorStop(0.3, `rgba(${r},${g},${b},0.3)`);
  grad.addColorStop(1, `rgba(${r},${g},${b},0)`);
  ctx.fillStyle = grad; ctx.fillRect(0, 0, s, s);
  const t = new THREE.CanvasTexture(cv); t.colorSpace = THREE.SRGBColorSpace; return t;
}

/* graphite disc + ivory rim + centred ivory icon — the app icon, as a node */
function nodeTexture(name) {
  const S = 256, cv = document.createElement("canvas");
  cv.width = cv.height = S;
  const ctx = cv.getContext("2d");
  const cx = S / 2, cy = S / 2, R = 96;

  ctx.beginPath(); ctx.arc(cx, cy, R, 0, Math.PI * 2);
  ctx.fillStyle = `rgba(${GRAPHITE},0.95)`; ctx.fill();

  const hi = ctx.createLinearGradient(0, cy - R, 0, cy + R);
  hi.addColorStop(0, `rgba(${IVORY},0.12)`);
  hi.addColorStop(0.55, "rgba(255,255,255,0)");
  ctx.save(); ctx.clip(); ctx.fillStyle = hi; ctx.fillRect(0, 0, S, S); ctx.restore();

  ctx.beginPath(); ctx.arc(cx, cy, R - 2.5, 0, Math.PI * 2);
  ctx.strokeStyle = `rgba(${IVORY},0.88)`; ctx.lineWidth = 5; ctx.stroke();

  const box = 100, scale = box / 24;
  ctx.save();
  ctx.translate(cx - box / 2, cy - box / 2); ctx.scale(scale, scale);
  ctx.strokeStyle = `rgba(${IVORY},0.97)`;
  ctx.lineWidth = 1.75; ctx.lineCap = "round"; ctx.lineJoin = "round";
  (ICONS[name] || ICONS.habits)(ctx);
  ctx.restore();

  const t = new THREE.CanvasTexture(cv);
  t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 4;
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
  camera.position.set(0, 0, 15);
  camera.lookAt(0, 0, 0);

  const system = new THREE.Group();
  system.rotation.x = 0.52;          // one tilt for the whole system
  scene.add(system);

  /* ---- central body: graphite sphere + ivory ring (the logo motif) ---- */
  const planet = new THREE.Group();
  system.add(planet);

  planet.add(new THREE.Mesh(
    new THREE.SphereGeometry(0.92, 64, 64),
    new THREE.MeshStandardMaterial({ color: 0x322D3C, roughness: 0.42, metalness: 0.28 })
  ));

  // ivory limb so the sphere reads as a body, not a hole
  const limb = new THREE.Sprite(new THREE.SpriteMaterial({
    map: (() => {
      const S = 256, cv = document.createElement("canvas");
      cv.width = cv.height = S;
      const c = cv.getContext("2d");
      c.beginPath(); c.arc(S / 2, S / 2, S / 2 - 8, 0, Math.PI * 2);
      c.strokeStyle = "rgba(255,255,255,0.55)"; c.lineWidth = 4; c.stroke();
      const t = new THREE.CanvasTexture(cv); t.colorSpace = THREE.SRGBColorSpace; return t;
    })(),
    transparent: true, depthWrite: false, depthTest: false,
  }));
  limb.scale.setScalar(1.94);
  planet.add(limb);

  const glow = new THREE.Sprite(new THREE.SpriteMaterial({
    map: radialTexture(0xCFC9BE), transparent: true, blending: THREE.AdditiveBlending,
    depthWrite: false, opacity: 0.3,
  }));
  glow.scale.setScalar(4.0);
  planet.add(glow);

  const ringPts = new THREE.EllipseCurve(0, 0, 1.95, 1.15, 0, Math.PI * 2)
    .getPoints(150).map((p) => new THREE.Vector3(p.x, p.y, 0));
  const ringMat = new THREE.LineBasicMaterial({ color: 0xF1EFEB, transparent: true, opacity: 0.62 });
  const ring = new THREE.LineLoop(new THREE.BufferGeometry().setFromPoints(ringPts), ringMat);
  ring.rotation.x = Math.PI / 2.1;
  ring.rotation.z = -0.5;
  planet.add(ring);

  /* ---- lights ---- */
  scene.add(new THREE.AmbientLight(0xb9b4c8, 0.7));
  const key = new THREE.PointLight(0xffffff, 2.2, 60); key.position.set(-5, 7, 9); scene.add(key);
  const rim = new THREE.PointLight(0xF1EFEB, 0.55, 60); rim.position.set(-8, -4, -6); scene.add(rim);

  /* ---- feature nodes on coplanar, evenly spaced circular orbits ---- */
  const sats = [];
  const pathMats = [];
  FEATURES.forEach(([name, tint], i) => {
    const radius = R0 + i * STEP;
    const speed = K / Math.pow(radius, 1.5);   // outer orbits move slower
    const phase = i * (Math.PI * 2 / FEATURES.length);

    const g = new THREE.Group();

    const halo = new THREE.Sprite(new THREE.SpriteMaterial({
      map: radialTexture(tint), transparent: true, blending: THREE.AdditiveBlending,
      depthWrite: false, opacity: 0.2,
    }));
    halo.scale.setScalar(2.1);
    g.add(halo);

    const node = new THREE.Sprite(new THREE.SpriteMaterial({
      map: nodeTexture(name), transparent: true, depthWrite: false,
    }));
    node.scale.setScalar(1.14);
    g.add(node);

    // the orbit path — same plane for every node
    const pts = new THREE.EllipseCurve(0, 0, radius, radius, 0, Math.PI * 2)
      .getPoints(160).map((p) => new THREE.Vector3(p.x, 0, p.y));
    const pathMat = new THREE.LineBasicMaterial({ color: 0xF1EFEB, transparent: true, opacity: 0.1 });
    pathMats.push(pathMat);
    system.add(new THREE.LineLoop(new THREE.BufferGeometry().setFromPoints(pts), pathMat));
    system.add(g);

    sats.push({ g, radius, speed, phase, halo });
  });

  /* ---- theme adaptation (the page has a light/dark toggle) ---- */
  function applyTheme() {
    const light = document.documentElement.getAttribute("data-theme") === "light";
    const lineCol = light ? 0x8A857C : 0xF1EFEB;
    ringMat.color.setHex(light ? 0x4A453E : 0xF1EFEB);
    ringMat.opacity = light ? 0.55 : 0.62;
    pathMats.forEach((m) => { m.color.setHex(lineCol); m.opacity = light ? 0.3 : 0.1; });
    limb.material.color.setHex(light ? 0x6F6B63 : 0xF1EFEB);
    glow.material.opacity = light ? 0.1 : 0.3;
    sats.forEach((s) => { s.baseHalo = light ? 0.1 : 0.2; });
  }
  applyTheme();
  new MutationObserver(applyTheme).observe(document.documentElement, {
    attributes: true, attributeFilter: ["data-theme"],
  });

  /* ---- sizing (square container) ---- */
  function resize() {
    const w = canvas.clientWidth || 480, h = canvas.clientHeight || 480;
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
  }
  resize();
  window.addEventListener("resize", resize);

  /* ---- gentle parallax ---- */
  let tx = 0, ty = 0, cx = 0, cy = 0;
  window.addEventListener("pointermove", (e) => {
    tx = e.clientX / window.innerWidth - 0.5;
    ty = e.clientY / window.innerHeight - 0.5;
  }, { passive: true });

  const clock = new THREE.Clock();
  const tmp = new THREE.Vector3();
  let rafId = null;

  function place(s, t) {
    const a = t * s.speed + s.phase;
    s.g.position.set(Math.cos(a) * s.radius, 0, Math.sin(a) * s.radius);
    const wz = s.g.getWorldPosition(tmp).z;
    const k = THREE.MathUtils.clamp((wz + 6) / 12, 0.2, 1);
    s.halo.material.opacity = (s.baseHalo ?? 0.2) * (0.5 + k);
    s.g.scale.setScalar(0.82 + k * 0.34);   // depth cue
  }

  function step() {
    const t = clock.getElapsedTime();
    for (const s of sats) place(s, t);
    planet.rotation.y = t * 0.12;
    system.rotation.y = t * 0.035;

    cx += (tx - cx) * 0.05; cy += (ty - cy) * 0.05;
    system.rotation.z = cx * 0.14;
    system.rotation.x = 0.52 + cy * 0.13;

    renderer.render(scene, camera);
    rafId = requestAnimationFrame(step);
  }

  if (reduceMotion) {
    for (const s of sats) place(s, 0);
    renderer.render(scene, camera);
  } else {
    rafId = requestAnimationFrame(step);
    if ("IntersectionObserver" in window) {
      new IntersectionObserver((entries) => {
        for (const en of entries) {
          if (en.isIntersecting && rafId === null) rafId = requestAnimationFrame(step);
          else if (!en.isIntersecting && rafId !== null) { cancelAnimationFrame(rafId); rafId = null; }
        }
      }, { threshold: 0.01 }).observe(canvas);
    }
  }
}

try { init(); } catch (e) { showFallbackOnly(); }
