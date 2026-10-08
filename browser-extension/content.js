// Marginalia for YouTube. On a video, press N to write a note or Q to ask a question about it in
// Marginalia, at the moment the video is at. The video pauses, and the app comes up with its note
// box open at that time (or first asks to add the video as a resource, if it isn't one yet).
//
// It talks to the app through a marginalia:// link, which Windows hands to Marginalia (see
// register_protocol.ps1 in the app's folder):
//   marginalia://capture?kind=note&url=<the video>&t=<seconds>&title=<its title>
(() => {
  "use strict";

  const KINDS = { n: "note", q: "question" };

  // Typing in YouTube's search box, a comment or the chat: the keys are letters, not commands.
  function isTyping(event) {
    const target = event.composedPath ? event.composedPath()[0] : event.target;
    if (!target || !target.tagName) return false;
    if (target.isContentEditable) return true;
    return ["input", "textarea", "select"].includes(target.tagName.toLowerCase());
  }

  // The video this page shows, as a plain watch link (no playlist, no start time), or null.
  function videoLink() {
    const url = new URL(location.href);
    const id = url.pathname === "/watch"
      ? url.searchParams.get("v")
      : (url.pathname.match(/^\/(?:shorts|live)\/([A-Za-z0-9_-]{11})/) || [])[1];
    return id && /^[A-Za-z0-9_-]{11}$/.test(id) ? `https://www.youtube.com/watch?v=${id}` : null;
  }

  function player() {
    return document.querySelector("#movie_player video.html5-main-video")
      || document.querySelector("ytd-reel-video-renderer[is-active] video")
      || document.querySelector("video");
  }

  function videoTitle() {
    const heading = document.querySelector("ytd-watch-metadata h1, h1.ytd-watch-metadata");
    const text = heading ? heading.textContent : document.title.replace(/\s*-\s*YouTube\s*$/, "");
    return text.replace(/^\(\d+\)\s*/, "").trim();   // "(3) Title": the notification count
  }

  function clock(seconds) {
    const h = Math.floor(seconds / 3600), m = Math.floor(seconds / 60) % 60, s = seconds % 60;
    const two = (n) => String(n).padStart(2, "0");
    return h > 0 ? `${h}:${two(m)}:${two(s)}` : `${m}:${two(s)}`;
  }

  // A short message in the corner of the page.
  let toastTimer = 0;
  function toast(text) {
    let box = document.getElementById("marginalia-toast");
    if (!box) {
      box = document.createElement("div");
      box.id = "marginalia-toast";
      Object.assign(box.style, {
        position: "fixed", left: "24px", bottom: "24px", zIndex: 2147483647,
        padding: "10px 16px", borderRadius: "12px",
        background: "linear-gradient(#3a2d22, #2f241b)", color: "#f1ece4",
        border: "1px solid rgba(255, 235, 210, 0.18)", boxShadow: "0 10px 28px rgba(0, 0, 0, 0.45)",
        font: "500 14px/1.3 'Segoe UI', Roboto, Arial, sans-serif",
        transition: "opacity 160ms ease", pointerEvents: "none",
      });
      document.documentElement.appendChild(box);
    }
    box.textContent = text;
    box.style.opacity = "1";
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { box.style.opacity = "0"; }, 2200);
  }

  document.addEventListener("keydown", (event) => {
    if (event.repeat || event.ctrlKey || event.metaKey || event.altKey || event.shiftKey) return;
    const kind = KINDS[event.key.toLowerCase()];
    if (!kind || isTyping(event)) return;
    const url = videoLink();
    if (!url) return;                                   // not on a video: leave the key alone

    event.preventDefault();
    event.stopImmediatePropagation();

    if (document.querySelector("#movie_player.ad-showing")) {
      toast("Marginalia: wait for the ad to finish");   // the time would be the ad's
      return;
    }
    const video = player();
    const seconds = video ? Math.floor(video.currentTime) : 0;
    if (video && !video.paused) video.pause();          // you're about to type

    const params = new URLSearchParams({ kind, url, t: String(seconds), title: videoTitle() });
    // Chrome hands the link to Windows, which starts (or wakes) Marginalia with it. The first time,
    // Chrome asks whether YouTube may open Marginalia: tick "Always allow".
    window.location.href = `marginalia://capture?${params}`;
    toast(`Marginalia: ${kind === "note" ? "note" : "question"} at ${clock(seconds)}`);
  }, true);
})();
