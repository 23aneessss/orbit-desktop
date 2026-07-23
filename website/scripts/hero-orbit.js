// Orbit hero — a 3D orbit built with Three.js (core only).
// A central "planet" with six feature satellites revolving on tilted elliptical
// orbits, additive glow, a starfield, and pointer parallax.
// Falls back gracefully when WebGL is unavailable or reduced motion is preferred.

import * as THREE from "three";

const canvas = document.getElementById("orbitScene");
const fallback = document.getElementById("heroFallback");
const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

function showFallbackOnly() {
  if (canvas) canvas.style.display = "none";
  if (fallback) fallback.style.opacity = "1";
}

// Feature satellites: [emoji, hex color, orbit radiusX, radiusZ, inclination(rad), speed, phase]
const FEATURES = [
  ["🔥", 0x10b981, 3.1, 2.2, 0.20, 0.34, 0.0],
  ["💡", 0xf59e0b, 4.3, 3.0, -0.32, 0.24, 1.1],
  ["🕸️", 0x3d6df2, 5.5, 3.9, 0.14, 0.19, 2.4],
  ["✓", 0xf43f5e, 2.4, 1.7, 0.42, 0.44, 3.3],
  ["👥", 0x0ea5a8, 6.4, 4.6, -0.18, 0.15, 4.6],
  ["⌘", 0x8b5cf6, 3.8, 5.2, 0.30, 0.28, 5.4],
];

function radialTexture(hex) {
  const s = 128;
  const c = document.createElement("canvas");
  c.width = c.height = s;
  const ctx = c.getContext("2d");
  const col = new THREE.Color(hex);
  const r = Math.round(col.r * 255), g = Math.round(col.g * 255), b = Math.round(col.b * 255);
  const grad = ctx.createRadialGradient(s / 2, s / 2, 0, s / 2, s / 2, s / 2);
  grad.addColorStop(0, `rgba(${r},${g},${b},0.95)`);
  grad.addColorStop(0.25, `rgba(${r},${g},${b},0.55)`);
  grad.addColorStop(1, `rgba(${r},${g},${b},0)`);
  ctx.fillStyle = grad;
  ctx.fillRect(0, 0, s, s);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

function iconTexture(glyph) {
  const s = 128;
  const c = document.createElement("canvas");
  c.width = c.height = s;
  const ctx = c.getContext("2d");
  ctx.fillStyle = "#ffffff";
  ctx.font = "600 66px -apple-system, 'SF Pro Display', system-ui, sans-serif";
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.fillText(glyph, s / 2, s / 2 + 4);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

function init() {
  let renderer;
  try {
    renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true, powerPreference: "high-performance" });
  } catch (e) {
    showFallbackOnly();
    return;
  }
  if (!renderer || !renderer.getContext()) { showFallbackOnly(); return; }

  const DPR = Math.min(window.devicePixelRatio || 1, 2);
  renderer.setPixelRatio(DPR);
  renderer.setClearColor(0x000000, 0);

  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(46, 1, 0.1, 100);
  camera.position.set(0, 1.6, 13.5);
  camera.lookAt(0, 0, 0);

  // The whole orbital system — tilted, gently spinning, parallax-reactive.
  const system = new THREE.Group();
  system.rotation.x = 0.42;
  system.position.y = 0.9; // lift the orbit so satellites clear the sub-headline
  scene.add(system);

  // ---- central planet ----
  const planet = new THREE.Group();
  system.add(planet);

  const sphereGeo = new THREE.SphereGeometry(1.15, 64, 64);
  const sphereMat = new THREE.MeshStandardMaterial({
    color: 0x7c53f0, emissive: 0x3a1d7a, emissiveIntensity: 0.55,
    roughness: 0.35, metalness: 0.1,
  });
  const core = new THREE.Mesh(sphereGeo, sphereMat);
  planet.add(core);

  // planet glow
  const planetGlow = new THREE.Sprite(new THREE.SpriteMaterial({
    map: radialTexture(0x8b5cf6), transparent: true, blending: THREE.AdditiveBlending, depthWrite: false, opacity: 0.9,
  }));
  planetGlow.scale.setScalar(5.4);
  planet.add(planetGlow);

  // orbit ring around the planet (the logo's ellipse)
  const ringCurve = new THREE.EllipseCurve(0, 0, 2.1, 1.25, 0, Math.PI * 2);
  const ringPts = ringCurve.getPoints(120).map((p) => new THREE.Vector3(p.x, p.y, 0));
  const ring = new THREE.LineLoop(
    new THREE.BufferGeometry().setFromPoints(ringPts),
    new THREE.LineBasicMaterial({ color: 0xc3a8ff, transparent: true, opacity: 0.5 })
  );
  ring.rotation.x = Math.PI / 2.1;
  ring.rotation.z = -0.5;
  planet.add(ring);

  // ---- lights ----
  scene.add(new THREE.AmbientLight(0x8877cc, 0.6));
  const key = new THREE.PointLight(0xffffff, 1.4, 40);
  key.position.set(6, 8, 10);
  scene.add(key);
  const rim = new THREE.PointLight(0x20a8ad, 1.1, 40);
  rim.position.set(-8, -3, -6);
  scene.add(rim);

  // ---- satellites ----
  const sats = [];
  for (const [glyph, color, rx, rz, incl, speed, phase] of FEATURES) {
    const g = new THREE.Group();

    const glow = new THREE.Sprite(new THREE.SpriteMaterial({
      map: radialTexture(color), transparent: true, blending: THREE.AdditiveBlending, depthWrite: false, opacity: 0.8,
    }));
    glow.scale.setScalar(1.6);
    g.add(glow);

    const chip = new THREE.Mesh(
      new THREE.SphereGeometry(0.34, 32, 32),
      new THREE.MeshStandardMaterial({ color, emissive: color, emissiveIntensity: 0.5, roughness: 0.4 })
    );
    g.add(chip);

    const icon = new THREE.Sprite(new THREE.SpriteMaterial({
      map: iconTexture(glyph), transparent: true, depthWrite: false, depthTest: false,
    }));
    icon.scale.setScalar(0.5);
    icon.position.z = 0.36;
    g.add(icon);

    // faint orbit path
    const curve = new THREE.EllipseCurve(0, 0, rx, rz, 0, Math.PI * 2);
    const pts = curve.getPoints(128).map((p) => new THREE.Vector3(p.x, 0, p.y));
    const path = new THREE.LineLoop(
      new THREE.BufferGeometry().setFromPoints(pts),
      new THREE.LineBasicMaterial({ color, transparent: true, opacity: 0.14 })
    );
    const holder = new THREE.Group();
    holder.rotation.x = incl;
    holder.add(path);
    holder.add(g);
    system.add(holder);

    sats.push({ g, rx, rz, speed, phase, glow });
  }

  // ---- starfield ----
  const starCount = window.innerWidth < 700 ? 260 : 620;
  const starPos = new Float32Array(starCount * 3);
  for (let i = 0; i < starCount; i++) {
    const r = 22 + Math.random() * 26;
    const th = Math.random() * Math.PI * 2;
    const ph = Math.acos(2 * Math.random() - 1);
    starPos[i * 3] = r * Math.sin(ph) * Math.cos(th);
    starPos[i * 3 + 1] = r * Math.sin(ph) * Math.sin(th);
    starPos[i * 3 + 2] = r * Math.cos(ph) - 6;
  }
  const starGeo = new THREE.BufferGeometry();
  starGeo.setAttribute("position", new THREE.BufferAttribute(starPos, 3));
  const stars = new THREE.Points(starGeo, new THREE.PointsMaterial({
    color: 0xffffff, size: 0.06, transparent: true, opacity: 0.55, depthWrite: false,
  }));
  scene.add(stars);

  // ---- sizing ----
  function resize() {
    const w = canvas.clientWidth || window.innerWidth;
    const h = canvas.clientHeight || window.innerHeight;
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    // pull the camera back a touch on narrow screens so nothing clips
    camera.position.z = w < 760 ? 17 : 13.5;
    camera.updateProjectionMatrix();
  }
  resize();
  window.addEventListener("resize", resize);

  // ---- parallax ----
  let targetX = 0, targetY = 0, curX = 0, curY = 0;
  window.addEventListener("pointermove", (e) => {
    targetX = (e.clientX / window.innerWidth - 0.5);
    targetY = (e.clientY / window.innerHeight - 0.5);
  }, { passive: true });

  const clock = new THREE.Clock();

  function frame() {
    const t = clock.getElapsedTime();

    for (const s of sats) {
      const a = t * s.speed + s.phase;
      s.g.position.set(Math.cos(a) * s.rx, 0, Math.sin(a) * s.rz);
      // depth cue: brighten & enlarge glow when closer to camera (world z)
      const wz = s.g.getWorldPosition(new THREE.Vector3()).z;
      const k = THREE.MathUtils.clamp((wz + 7) / 14, 0.25, 1);
      s.glow.material.opacity = 0.4 + k * 0.6;
      s.g.scale.setScalar(0.75 + k * 0.5);
    }

    planet.rotation.y = t * 0.15;
    system.rotation.y = t * 0.05;
    stars.rotation.y = t * 0.01;

    curX += (targetX - curX) * 0.05;
    curY += (targetY - curY) * 0.05;
    system.rotation.z = curX * 0.25;
    system.rotation.x = 0.42 + curY * 0.22;
    camera.position.x = curX * 1.4;
    camera.lookAt(0, 0, 0);

    renderer.render(scene, camera);
    if (!reduceMotion) rafId = requestAnimationFrame(frame);
  }

  let rafId;
  renderer.render(scene, camera);
  if (reduceMotion) {
    // one composed frame, no animation loop
    for (let i = 0; i < sats.length; i++) {
      const s = sats[i], a = s.phase;
      s.g.position.set(Math.cos(a) * s.rx, 0, Math.sin(a) * s.rz);
    }
    renderer.render(scene, camera);
  } else {
    rafId = requestAnimationFrame(frame);
    // pause when the hero is off-screen to save the GPU
    const hero = document.querySelector(".hero");
    if (hero && "IntersectionObserver" in window) {
      new IntersectionObserver((entries) => {
        for (const en of entries) {
          if (en.isIntersecting && rafId == null) { rafId = requestAnimationFrame(frame); }
          else if (!en.isIntersecting && rafId != null) { cancelAnimationFrame(rafId); rafId = null; }
        }
      }, { threshold: 0.01 }).observe(hero);
    }
  }
}

if (reduceMotion) {
  // still draw a static scene for a nice first paint, but guard WebGL support
  try { init(); } catch (e) { showFallbackOnly(); }
} else {
  try { init(); } catch (e) { showFallbackOnly(); }
}
