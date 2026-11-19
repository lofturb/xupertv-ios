/* XuperTV iOS - interfaz propia, adaptativa, sin lienzo fijo 1920. */
(function () {
  "use strict";

  var $ = function (id) { return document.getElementById(id); };
  var AM = "&";
  var catalog = [];
  var state = { view: "home", item: null, season: 0 };

  function esc(v) {
    return String(v == null ? "" : v)
      .split(AM + AM).join(AM + "amp;")
      .split("<").join(AM + "lt;")
      .split(">").join(AM + "gt;")
      .split('"').join(AM + "quot;");
  }

  function toast(msg) {
    var t = $("toast");
    if (!t) return;
    t.textContent = msg;
    t.classList.add("on");
    clearTimeout(toast.t);
    toast.t = setTimeout(function () { t.classList.remove("on"); }, 2200);
  }

  var pending = {};
  var seq = 0;

  window.__uiResolve = function (id, json) {
    var fn = pending[String(id)];
    if (!fn) return;
    delete pending[String(id)];
    var data = null;
    try { data = JSON.parse(json); } catch (e) { data = null; }
    fn(data);
  };

  function call(method, params) {
    return new Promise(function (resolve) {
      var mh = window.webkit && window.webkit.messageHandlers;
      if (!mh || !mh.xuperService) { resolve(null); return; }
      var id = "ui" + (++seq);
      pending[id] = resolve;
      setTimeout(function () {
        if (!pending[id]) return;
        delete pending[id];
        resolve(null);
      }, 40000);
      try {
        mh.xuperService.postMessage({
          id: id,
          service: "luna://com.webosflux.xupertv.fidelity.service/" + method,
          payload: JSON.stringify(params || {})
        });
      } catch (e) { delete pending[id]; resolve(null); }
    });
  }

  function pickImage(it) {
    var list = [it.poster, it.landscape, it.backdrop, it.cover, it.thumb];
    for (var i = 0; i < list.length; i++) {
      if (list[i] && typeof list[i] === "string") return list[i];
    }
    return "";
  }

  function cardHTML(it) {
    var img = pickImage(it);
    var ph = img ? '<img src="' + esc(img) + '" alt="">'
                 : '<div class="fallback">' + esc(it.title) + "</div>";
    var id = esc(it.id);
    var title = esc(it.title);
    return '<button class="card" data-id="' + id + '">' +
           '<div class="ph">' + ph + '</div>' +
           '<div class="t">' + title + '</div></button>';
  }

  function renderGrid(list) {
    var host = $("content");
    if (!list || !list.length) {
      host.innerHTML = '<div class="empty">No hay contenidos.</div>';
      return;
    }
    var html = '<div class="grid">';
    for (var i = 0; i < list.length; i++) html += cardHTML(list[i]);
    host.innerHTML = html + '</div>';
  }

  function overlay() { return $("overlay"); }

  function closeOverlay() {
    var o = overlay();
    o.hidden = true;
    o.querySelector(".overlay-actions").innerHTML = "";
    o.querySelector(".overlay-body").innerHTML = "";
    var v = o.querySelector("video");
    if (v) {
      try { v.pause(); } catch (e) {}
      v.removeAttribute("src");
    }
  }

  function showOverlay(title, body, actionsRev) {
    var o = overlay();
    o.hidden = false;
    o.querySelector(".overlay-title").textContent = title || "";
    o.querySelector(".overlay-body").innerHTML = body || "";
    var bar = o.querySelector(".overlay-actions");
    bar.innerHTML = "";
    if (!actionsRev) return bar;
    for (var i = 0; i < actionsRev.length; i++) {
      (function (a) {
        var b = document.createElement("button");
        b.className = "ghost";
        b.textContent = a.label;
        b.onclick = a.fn;
        bar.appendChild(b);
      })(actionsRev[i]);
    }
    return bar;
  }

  function openDetail(id) {
    var it = itemFromId(id);
    if (!it) return;
    state.item = it;
    state.season = 0;
    var img = pickImage(it);
    var head = '<div class="detail-head">';
    if (img) head += '<img src="' + esc(img) + '" alt="">';
    head += '<div class="detail-meta">';
    head += '<div class="detail-title">' + esc(it.title) + "</div>";
    if (it.kind) head += '<div class="detail-sub">' + esc(it.kind) + "</div>";
    if (it.synopsis) head += '<div class="detail-syn">' + esc(it.synopsis) + "</div>";
    head += '<div class="seasons" id="seasons"></div></div></div>';
    head += '<div class="episodes" id="episodes"></div>';
    showOverlay(it.title || "", head, [
      { label: "Reproducir", fn: function () { playItem(it, null); } },
      { label: "Volver", fn: closeOverlay }
    ]);
    loadSeasons(it);
  }


  function loadSeasons(it) {
    var box = $("seasons");
    var eps = $("episodes");
    if (!box || !eps) return;
    eps.innerHTML = spinner();
    call("detail", { contentId: it.id }).then(function (res) {
      if (!res || res.returnValue === false) {
        eps.innerHTML = '<div class="empty">No se pudo abrir.</div>';
        return;
      }
      var seasons = res.seasons || [];
      if (!seasons.length) {
        state.season = 0;
        renderEpisodes(it, (res.episodes || []));
        return;
      }
      box.innerHTML = "";
      seasons.forEach(function (s, idx) {
        var b = document.createElement("button");
        b.className = "season-btn" + (idx === 0 ? " on" : "");
        b.textContent = "T" + (s.number || idx + 1);
        b.onclick = function () {
          state.season = idx;
          var all = box.querySelectorAll(".season-btn");
          for (var k = 0; k < all.length; k++) all[k].className = "season-btn";
          b.className = "season-btn on";
          eps.innerHTML = spinner();
          call("detail", { contentId: s.id, seriesContentId: it.id }).then(function (r2) {
            var list = (r2 && r2.episodes) || [];
            if (!list.length && r2 && r2.item && r2.item.episodes) list = r2.item.episodes;
            renderEpisodes(it, list);
          });
        };
        box.appendChild(b);
      });
      if (res.episodes && res.episodes.length) renderEpisodes(it, res.episodes);
    });
  }

  function renderEpisodes(it, list) {
    state.episodes = list || [];
    var eps = $("episodes");
    if (!list || !list.length) {
      eps.innerHTML = '<div class="empty">Sin capitulos.</div>';
      return;
    }
    var html = "";
    for (var i = 0; i < list.length; i++) {
      var ep = list[i];
      var n = ep.number || i + 1;
      html += '<button class="ep" data-ep="' + esc(ep.id) + '">' +
              '<span class="num">' + esc(n) + "</span>" +
              '<span class="name">' + esc(ep.title || ("Capitulo " + n)) + "</span>" +
              "</button>";
    }
    eps.innerHTML = html;
  }


  function playItem(it, ep) {
    var params = {
      contentId: ep && ep.id ? ep.id : it.id,
      seriesContentId: ep ? it.id : it.seasonId,
      quality: "720",
      hevc: false,
      uhd: false,
      trackIndex: 0,
      audioPreference: "es-lat",
      audioTrack: 0
    };
    if (!params.seriesContentId) delete params.seriesContentId;
    var title = it.title || "";
    if (ep && ep.title) title += " - " + ep.title;
    showOverlay(title, spinner(), [
      { label: "Volver", fn: function () { openDetail(it.id); } }
    ].concat([{ label: "Cerrar", fn: closeOverlay }]));
    call("resolve", params).then(function (res) {
      var src = res && res.remoteUrl;
      if (!src && window.__xuperIosNative && window.__xuperPlayVlc) {
        window.__xuperPlayVlc("", {}, title);
        closeOverlay();
      }
      if (!src) {
        closeOverlay();
        toast("No se pudo resolver el video");
        return;
      }
      playVlc(src, (res && res.remoteHeaders) || {}, title);
    });
  }

  function playVlc(url, headers, title) {
    if (window.__xuperIosNative && window.__xuperPlayVlc) {
      window.__xuperPlayVlc(url, headers, title);
      closeOverlay();
      return;
    }
    var body = '<div class="detail-syn">' + esc(title) + "</div>";
    var bar = showOverlay(title || "", body, [
      { label: "Cerrar", fn: closeOverlay }
    ]);
    var v = document.createElement("video");
    v.controls = true;
    v.autoplay = true;
    v.playsInline = true;
    v.style.width = "100%";
    v.src = url;
    bar.parentNode.insertBefore(v, bar);
    try { v.play(); } catch (e) {}
  }


  function bindEvents() {
    var nav = document.querySelectorAll(".nav-item");
    for (var i = 0; i < nav.length; i++) {
      nav[i].onclick = function () {
        var v = this.getAttribute("data-view");
        if (v === "search") { openSearch(); return; }
        if (v === "history") { openHistory(); return; }
        loadHome(v);
      };
    }

    $("content").onclick = function (ev) {
      var el = ev.target;
      while (el && el !== this) {
        if (el.className === "card") return openDetail(el.getAttribute("data-id"));
        if (el.className === "ep") return openEpisode(el.getAttribute("data-ep"));
        el = el.parentNode;
      }
    };

    var rb = $("btn-reload");
    if (rb) rb.onclick = function () { loadHome(state.view); };

    var sb = $("btn-search-cancel");
    if (sb) sb.onclick = closeSearch;

    var si = $("search-input");
    if (si) {
      si.onkeydown = function (e) {
        if (e.keyCode === 13) runSearch(si.value);
      };
    }
  }

  function openEpisode(epId) {
    var it = state.item;
    if (!it) return;
    var ep = null;
    var list = state.episodes || [];
    for (var i = 0; i < list.length; i++) {
      if (String(list[i].id) === String(epId)) ep = list[i];
    }
    playItem(it, ep);
  }


  function openSearch() {
    var sb = $("searchbar");
    sb.hidden = false;
    var si = $("search-input");
    si.value = "";
    si.focus();
  }

  function closeSearch() {
    $("searchbar").hidden = true;
    loadHome(state.view);
  }

  function runSearch(text) {
    var q = String(text || "").trim();
    $("searchbar").hidden = true;
    setActiveNav("search");
    setTitle("Buscar: " + q);
    $("content").innerHTML = spinner();
    call("search", { value: q, pageNum: 1 }).then(function (res) {
      catalog = (res && res.items) || [];
      renderGrid(catalog);
    });
  }

  function openHistory() {
    setActiveNav("history");
    setTitle("Historial");
    $("content").innerHTML = spinner();
    call("history", {}).then(function (res) {
      var list = (res && (res.items || res.history)) || [];
      if (!list.length) {
        $("content").innerHTML = '<div class="empty">Aun no hay historial.</div>';
        return;
      }
      catalog = list;
      renderGrid(catalog);
    });
  }

  bindEvents();
  loadHome("home");
})();


