// Scroll-reveal
const io = new IntersectionObserver((entries) => {
  for (const e of entries) {
    if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); }
  }
}, { threshold: 0.12, rootMargin: "0px 0px -8% 0px" });
document.querySelectorAll(".reveal").forEach((el) => io.observe(el));

// Copy-to-clipboard for any element carrying a data-copy payload
document.querySelectorAll("[data-copy]").forEach((box) => {
  const btn = box.querySelector(".copy");
  if (!btn) return;
  btn.addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(box.getAttribute("data-copy"));
      const old = btn.textContent;
      btn.textContent = "Copied";
      btn.classList.add("done");
      setTimeout(() => { btn.textContent = old; btn.classList.remove("done"); }, 1600);
    } catch (_) {}
  });
});

// Snappy in-page navigation: fixed-duration eased scroll + reveal the
// destination immediately so it's never blank during the jump.
const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
const NAV_OFFSET = 72;
function easeInOutCubic(t) { return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2; }
function smoothScrollTo(targetY, dur = 460) {
  if (reduceMotion) { window.scrollTo(0, targetY); return; }
  const startY = window.scrollY, dist = targetY - startY, t0 = performance.now();
  function step(now) {
    const p = Math.min((now - t0) / dur, 1);
    window.scrollTo(0, startY + dist * easeInOutCubic(p));
    if (p < 1) requestAnimationFrame(step);
  }
  requestAnimationFrame(step);
}
document.querySelectorAll('a[href^="#"]').forEach((a) => {
  a.addEventListener("click", (e) => {
    const id = a.getAttribute("href");
    if (!id || id.length < 2) return;
    const el = document.querySelector(id);
    if (!el) return;
    e.preventDefault();
    // reveal destination instantly (no blank fade while we land)
    if (el.classList.contains("reveal")) el.classList.add("in");
    el.querySelectorAll(".reveal").forEach((r) => r.classList.add("in"));
    const y = el.getBoundingClientRect().top + window.scrollY - NAV_OFFSET;
    smoothScrollTo(Math.max(0, y));
    history.pushState(null, "", id);
  });
});

// Nav: solidify on scroll
const nav = document.getElementById("nav");
const onScroll = () => nav.classList.toggle("scrolled", window.scrollY > 12);
onScroll();
window.addEventListener("scroll", onScroll, { passive: true });

// Nav: highlight the section currently in view
const navLinks = [...document.querySelectorAll(".nav-links a")];
const sections = navLinks
  .map((a) => document.querySelector(a.getAttribute("href")))
  .filter(Boolean);
if (sections.length) {
  const spy = new IntersectionObserver((entries) => {
    for (const e of entries) {
      if (e.isIntersecting) {
        const id = "#" + e.target.id;
        navLinks.forEach((a) => a.classList.toggle("active", a.getAttribute("href") === id));
      }
    }
  }, { rootMargin: "-45% 0px -50% 0px" });
  sections.forEach((s) => spy.observe(s));
}

// Subtle parallax tilt on the hero app window (pointer only)
const app = document.querySelector(".hero-app");
if (app && matchMedia("(pointer:fine)").matches) {
  const win = app.querySelector(".window");
  // Once the intro pop finishes, drop the animation so hover-tilt isn't overridden by its held fill state.
  win.addEventListener("animationend", () => { win.style.animation = "none"; }, { once: true });
  app.addEventListener("pointermove", (e) => {
    const r = app.getBoundingClientRect();
    const x = (e.clientX - r.left) / r.width - 0.5;
    const y = (e.clientY - r.top) / r.height - 0.5;
    win.style.transform = `rotateY(${-8 - x * 10}deg) rotateX(${4 + y * 8}deg)`;
  });
  app.addEventListener("pointerleave", () => { win.style.transform = ""; });
}
