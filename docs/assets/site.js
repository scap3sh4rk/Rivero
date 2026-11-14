// Theme toggle (remembered) and "on this page" highlighting. No dependencies.
(function () {
  var root = document.documentElement;
  try {
    var saved = localStorage.getItem("rivero-docs-theme");
    if (saved) root.setAttribute("data-theme", saved);
  } catch (e) {}

  var btn = document.getElementById("theme");
  function isLight() {
    var t = root.getAttribute("data-theme");
    if (t) return t === "light";
    return window.matchMedia && window.matchMedia("(prefers-color-scheme: light)").matches;
  }
  function paint() { if (btn) btn.textContent = isLight() ? "☾" : "☀"; if (btn) btn.setAttribute("aria-label", isLight() ? "Switch to dark" : "Switch to light"); }
  if (btn) {
    btn.addEventListener("click", function () {
      var next = isLight() ? "dark" : "light";
      root.setAttribute("data-theme", next);
      try { localStorage.setItem("rivero-docs-theme", next); } catch (e) {}
      paint();
    });
    paint();
  }

  var links = document.querySelectorAll(".toc a");
  if (!links.length || !("IntersectionObserver" in window)) return;
  var map = {};
  links.forEach(function (a) { map[a.getAttribute("href").slice(1)] = a; });
  var io = new IntersectionObserver(function (entries) {
    entries.forEach(function (e) {
      if (e.isIntersecting && map[e.target.id]) {
        links.forEach(function (a) { a.classList.remove("on"); });
        map[e.target.id].classList.add("on");
      }
    });
  }, { rootMargin: "-90px 0px -70% 0px" });
  Object.keys(map).forEach(function (id) {
    var el = document.getElementById(id);
    if (el) io.observe(el);
  });
})();
