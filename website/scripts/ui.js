/* Orbit site — nav, theme, scroll reveals, screenshot tilt, mini-canvas, download link */
(function () {
  "use strict";

  // ⚠️ REPLACE OWNER/REPO with your GitHub repo. This always serves the newest release asset.
  var DOWNLOAD_URL = "https://github.com/OWNER/REPO/releases/latest/download/Orbit.dmg";

  var reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  document.addEventListener("DOMContentLoaded", function () {
    wireDownload();
    wireYear();
    wireThemeToggle();
    wireNavScroll();
    wireReveal();
    wireTilt();
    buildMiniCanvas();
  });

  function wireDownload() {
    document.querySelectorAll(".js-download").forEach(function (a) {
      // keep the nav "Download" pointing to the section; make the real CTAs download
      if (a.getAttribute("href") === "#download") return;
      a.setAttribute("href", DOWNLOAD_URL);
      a.setAttribute("rel", "noopener");
    });
  }

  function wireYear() {
    var y = document.getElementById("year");
    if (y) y.textContent = new Date().getFullYear();
  }

  function wireThemeToggle() {
    var root = document.documentElement;
    var saved = null;
    try { saved = localStorage.getItem("orbit-theme"); } catch (e) {}
    if (saved === "light" || saved === "dark") root.setAttribute("data-theme", saved);

    var btn = document.getElementById("themeToggle");
    if (!btn) return;
    btn.addEventListener("click", function () {
      var cur = root.getAttribute("data-theme") || "dark";
      var next = cur === "dark" ? "light" : "dark";
      root.setAttribute("data-theme", next);
      try { localStorage.setItem("orbit-theme", next); } catch (e) {}
    });
  }

  function wireNavScroll() {
    var nav = document.getElementById("nav");
    if (!nav) return;
    var onScroll = function () { nav.classList.toggle("is-stuck", window.scrollY > 8); };
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
  }

  function wireReveal() {
    var els = document.querySelectorAll("[data-reveal]");
    if (reduceMotion || !("IntersectionObserver" in window)) {
      els.forEach(function (el) { el.classList.add("is-in"); });
      return;
    }
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (en.isIntersecting) { en.target.classList.add("is-in"); io.unobserve(en.target); }
      });
    }, { threshold: 0.12, rootMargin: "0px 0px -8% 0px" });
    els.forEach(function (el) { io.observe(el); });
  }

  function wireTilt() {
    if (reduceMotion) return;
    document.querySelectorAll("[data-tilt]").forEach(function (fig) {
      var frame = fig.querySelector(".shot__frame");
      if (!frame) return;
      fig.addEventListener("pointermove", function (e) {
        var r = fig.getBoundingClientRect();
        var px = (e.clientX - r.left) / r.width - 0.5;
        var py = (e.clientY - r.top) / r.height - 0.5;
        frame.style.setProperty("--ry", (px * 7).toFixed(2) + "deg");
        frame.style.setProperty("--rx", (-py * 6).toFixed(2) + "deg");
      });
      fig.addEventListener("pointerleave", function () {
        frame.style.setProperty("--ry", "0deg");
        frame.style.setProperty("--rx", "0deg");
      });
    });
  }

  /* ---------- interactive mini-canvas (native React-Flow proof) ---------- */
  function buildMiniCanvas() {
    var host = document.getElementById("miniCanvas");
    var svg = document.getElementById("miniEdges");
    if (!host || !svg) return;

    var NODES = [
      { id: "a", title: "Why CRMs fail", tag: "product", x: 18, y: 30 },
      { id: "b", title: "Atomic Habits", tag: "books", x: 210, y: 150 },
      { id: "c", title: "Voice → note", tag: "ai", x: 30, y: 165 },
    ];
    var EDGES = [{ from: "a", to: "b" }];
    var els = {};

    NODES.forEach(function (n) {
      var el = document.createElement("div");
      el.className = "mininode";
      el.style.left = n.x + "px";
      el.style.top = n.y + "px";
      el.innerHTML = "<svg class='ic'><use href='#ic-ideas'/></svg>" + n.title +
        "<small>#" + n.tag + "</small><span class='miniport' data-port='" + n.id + "'></span>";
      host.appendChild(el);
      els[n.id] = { el: el, node: n };
      n.el = el;
    });

    var W = "http://www.w3.org/2000/svg";
    function centerRight(n) { return { x: n.x + n.el.offsetWidth, y: n.y + n.el.offsetHeight / 2 }; }
    function centerLeft(n) { return { x: n.x, y: n.y + n.el.offsetHeight / 2 }; }

    function draw() {
      while (svg.firstChild) svg.removeChild(svg.firstChild);
      EDGES.forEach(function (e) {
        var f = centerRight(els[e.from].node);
        var t = centerLeft(els[e.to].node);
        addPath(f, t, "var(--accent)", 0.85);
      });
      if (temp) addPath(temp.from, temp.to, "var(--accent)", 0.5);
    }
    function addPath(f, t, color, op) {
      var dx = Math.max(40, Math.abs(t.x - f.x) * 0.5);
      var d = "M " + f.x + " " + f.y + " C " + (f.x + dx) + " " + f.y + " " + (t.x - dx) + " " + t.y + " " + t.x + " " + t.y;
      var p = document.createElementNS(W, "path");
      p.setAttribute("d", d);
      p.setAttribute("fill", "none");
      p.setAttribute("stroke", color);
      p.setAttribute("stroke-width", "2");
      p.setAttribute("stroke-opacity", op);
      svg.appendChild(p);
    }

    var temp = null;
    var dragNode = null, dragOff = null, connectFrom = null;

    host.addEventListener("pointerdown", function (e) {
      var port = e.target.closest(".miniport");
      var node = e.target.closest(".mininode");
      var rect = host.getBoundingClientRect();
      if (port) {
        connectFrom = port.getAttribute("data-port");
        var f = centerRight(els[connectFrom].node);
        temp = { from: f, to: { x: e.clientX - rect.left, y: e.clientY - rect.top } };
        host.setPointerCapture(e.pointerId);
        e.preventDefault();
      } else if (node) {
        var id = Object.keys(els).find(function (k) { return els[k].el === node; });
        dragNode = els[id].node;
        dragOff = { x: e.clientX - rect.left - dragNode.x, y: e.clientY - rect.top - dragNode.y };
        node.classList.add("is-sel");
        host.setPointerCapture(e.pointerId);
      }
    });

    host.addEventListener("pointermove", function (e) {
      if (!dragNode && !connectFrom) return;
      var rect = host.getBoundingClientRect();
      var mx = e.clientX - rect.left, my = e.clientY - rect.top;
      if (dragNode) {
        dragNode.x = clamp(mx - dragOff.x, 0, host.clientWidth - dragNode.el.offsetWidth);
        dragNode.y = clamp(my - dragOff.y, 0, host.clientHeight - dragNode.el.offsetHeight);
        dragNode.el.style.left = dragNode.x + "px";
        dragNode.el.style.top = dragNode.y + "px";
        draw();
      } else if (connectFrom) {
        temp.to = { x: mx, y: my };
        draw();
      }
    });

    host.addEventListener("pointerup", function (e) {
      if (connectFrom) {
        var target = e.target.closest(".mininode");
        if (target) {
          var id = Object.keys(els).find(function (k) { return els[k].el === target; });
          if (id && id !== connectFrom && !EDGES.some(function (x) { return x.from === connectFrom && x.to === id; })) {
            EDGES.push({ from: connectFrom, to: id });
          }
        }
      }
      if (dragNode) dragNode.el.classList.remove("is-sel");
      dragNode = null; connectFrom = null; temp = null;
      draw();
    });

    function clamp(v, a, b) { return Math.max(a, Math.min(b, v)); }

    // initial paint (after layout settles)
    requestAnimationFrame(draw);
    window.addEventListener("resize", draw);
  }
})();
