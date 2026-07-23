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

## Two things to set

1. **Download link.** Open `scripts/ui.js` and replace `OWNER/REPO` in `DOWNLOAD_URL`
   with your GitHub repo. The URL `…/releases/latest/download/Orbit.dmg` always serves
   the newest release asset — just upload `Orbit.dmg` to a GitHub Release named so the
   asset is `Orbit.dmg`.
2. **(Optional) DMG size.** In `index.html`, the download line has a `#dmgSize` span you
   can fill in (e.g. `24 MB`).

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
