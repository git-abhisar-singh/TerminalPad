#!/usr/bin/env python3
"""Fetch white brand logos (simpleicons) -> rasterize via qlmanage -> Resources/logos/<key>.png.
Transparent PNGs; the app draws them on glass tiles. Misses are fine (monogram fallback)."""
import os, sys, subprocess, tempfile, urllib.request, shutil
from PIL import Image

ROOT = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(ROOT, "Resources", "logos")
os.makedirs(OUT, exist_ok=True)

# key -> candidate simpleicons slugs (first that returns 200 wins).
# key is the logo slug the app looks up (== command name, or Discovery.logoSlug mapping).
TARGETS = {
    # AI agents
    "claude": ["claude", "anthropic"], "gemini": ["googlegemini"], "ollama": ["ollama"],
    "opencode": ["opencode"], "antigravity": ["antigravity"],
    # languages / runtimes
    "node": ["nodedotjs"], "python": ["python"], "go": ["go"], "rust": ["rust"],
    "ruby": ["ruby"], "php": ["php"], "deno": ["deno"], "bun": ["bun"],
    "openjdk": ["openjdk"], "dotnet": ["dotnet"], "elixir": ["elixir"],
    # package mgrs
    "pipx": ["pypi"], "pnpm": ["pnpm"], "yarn": ["yarn"], "bundler": ["rubygems"],
    "composer": ["composer"], "cargo": ["rust"], "deno": ["deno"],
    # databases
    "redis": ["redis"], "postgresql": ["postgresql"], "mysql": ["mysql"],
    "mongodb": ["mongodb"], "sqlite": ["sqlite"],
    # devops / cloud
    "docker": ["docker"], "kubectl": ["kubernetes"], "terraform": ["terraform"],
    "ansible": ["ansible"], "vault": ["vault"], "gcloud": ["googlecloud"],
    "ngrok": ["ngrok"], "cloudflared": ["cloudflare"], "vercel": ["vercel"],
    "heroku": ["heroku"], "podman": ["podman"], "helm": ["helm"],
    # cli tools
    "gh": ["github"], "git": ["git"], "ffmpeg": ["ffmpeg"], "vim": ["vim"],
    "neovim": ["neovim"], "tmux": ["tmux"], "htop": ["htop"], "curl": ["curl"],
    "wget": ["gnu"], "jq": ["jq"], "fzf": ["fzf"],
    "ripgrep": ["ripgrep"], "lazygit": ["lazygit"], "pandoc": ["pandoc"],
    "imagemagick": ["imagemagick"], "yt-dlp": ["youtube"], "vlc": ["vlcmediaplayer"],
    "scrcpy": ["scrcpy"], "espeak-ng": ["espeakng"],
}

def fetch_svg(slug):
    # request BLACK logo; qlmanage flattens on white, then we key out white -> white-on-transparent
    url = f"https://cdn.simpleicons.org/{slug}/000000"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "agentpad"})
        with urllib.request.urlopen(req, timeout=8) as r:
            if r.status == 200:
                data = r.read()
                if b"<svg" in data:
                    return data
    except Exception:
        pass
    return None

def rasterize(svg_bytes, out_png):
    with tempfile.TemporaryDirectory() as td:
        svg = os.path.join(td, "i.svg")
        with open(svg, "wb") as f:
            f.write(svg_bytes)
        subprocess.run(["qlmanage", "-t", "-s", "1024", "-o", td, svg],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        gen = os.path.join(td, "i.svg.png")
        if not os.path.exists(gen):
            return False
        # black-on-white -> white-on-transparent (alpha = darkness), trim to content
        g = Image.open(gen).convert("L")
        alpha = g.point(lambda p: 255 - p)
        white = Image.new("RGBA", g.size, (255, 255, 255, 255))
        white.putalpha(alpha)
        bb = white.getbbox()
        if bb:
            white = white.crop(bb)
        # pad to square so logos sit consistently on tiles
        s = max(white.size)
        canvas = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        canvas.alpha_composite(white, ((s - white.size[0]) // 2, (s - white.size[1]) // 2))
        canvas.save(out_png)
        return True
    return False

hits, misses = [], []
for key, slugs in TARGETS.items():
    done = False
    for slug in slugs:
        svg = fetch_svg(slug)
        if svg and rasterize(svg, os.path.join(OUT, f"{key}.png")):
            hits.append(f"{key}<-{slug}")
            done = True
            break
    if not done:
        misses.append(key)

print("HITS:", ", ".join(hits))
print("MISS:", ", ".join(misses))
