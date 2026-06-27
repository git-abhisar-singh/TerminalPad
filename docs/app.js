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

// Subtle parallax tilt on the hero app window (pointer only)
const app = document.querySelector(".hero-app");
if (app && matchMedia("(pointer:fine)").matches) {
  const win = app.querySelector(".window");
  app.addEventListener("pointermove", (e) => {
    const r = app.getBoundingClientRect();
    const x = (e.clientX - r.left) / r.width - 0.5;
    const y = (e.clientY - r.top) / r.height - 0.5;
    win.style.transform = `rotateY(${-8 - x * 10}deg) rotateX(${4 + y * 8}deg)`;
  });
  app.addEventListener("pointerleave", () => { win.style.transform = ""; });
}
