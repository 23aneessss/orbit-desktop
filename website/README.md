# Orbit — marketing website

A self-contained static site (vanilla HTML/CSS/JS + a locally-vendored Three.js).
No build step, no runtime CDNs. Just static files.

```
website/
├── index.html
├── styles/main.css
├── scripts/
│   ├── hero-orbit.js        # WebGL 3D orbit hero (Three.js)
│   ├── ui.js                # nav, theme, scroll reveal, mini-canvas, download link
│   └── vendor/three.module.min.js
├── assets/
│   ├── orbit-icon.svg
│   └── screens/*.png        # real light-mode app screenshots (fictional demo data)
└── vercel.json
```

## Download link

The two "Download for macOS" buttons in `index.html` are plain `<a href>` pointing at:

```
https://github.com/23aneessss/orbit-desktop/releases/latest/download/Orbit.dmg
```

`latest/download/` always resolves to the newest release, so you never touch the site
again — just publish a new release whose asset is named **`Orbit.dmg`**:

```bash
gh release create v1.1.0 dist/Orbit.dmg --title "Orbit 1.1.0" --notes "…"
```

The links are deliberately **not** injected by JavaScript: a plain href can't go stale
against a cached script, and it still works with JS disabled. If you change the repo
name, grep `index.html` for `releases/latest`. The displayed size lives in the
`#dmgSize` span in `index.html`.

## Run locally

Any static server works, e.g.:

```bash
cd website
python3 -m http.server 5173
# open http://localhost:5173
```

## Deploy to Vercel

The site lives in `/website` inside the app repo. In Vercel:

1. **New Project → Import** this Git repository.
2. **Root Directory:** `website`
3. **Framework Preset:** Other
4. **Build Command:** *(leave empty)* · **Output Directory:** *(leave empty / `.`)*
5. Deploy. Every push to the branch redeploys automatically.

(Netlify / Cloudflare Pages / GitHub Pages work the same way — point them at the
`website` folder with no build command.)

## Screenshots

The product screenshots in `assets/screens/` are real captures of the Orbit app running
against a **throwaway, isolated store seeded with fictional demo data** — never the
owner's real data. Regenerate them from that demo build if the UI changes.
