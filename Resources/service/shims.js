/* XuperTV iOS - shims ES5 para ejecutar magis.js (Node) dentro de JavaScriptCore.
 * La red, 3DES y los timers se resuelven en Objective-C mediante puentes.
 */
var __dirname = "/service";
var __seedsFallback = null;
var __serviceModule = { exports: {} };
var module = __serviceModule;
var exports = module.exports;

/* Los puentes nativos (__nativeHTTP, __native3DES, __nativeTimer, ...) los
 * inyecta Objective-C en el JSContext antes de cargar este archivo. */

var B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
function b64encode(bytes) {
  var out = "", i, b0, b1, b2;
  for (i = 0; i < bytes.length; i += 3) {
    b0 = bytes[i] & 255;
    b1 = i + 1 < bytes.length ? bytes[i + 1] & 255 : 0;
    b2 = i + 2 < bytes.length ? bytes[i + 2] & 255 : 0;
    out += B64.charAt(b0 >> 2);
    out += B64.charAt(((b0 & 3) << 4) | (b1 >> 4));
    out += i + 1 < bytes.length ? B64.charAt(((b1 & 15) << 2) | (b2 >> 6)) : "=";
    out += i + 2 < bytes.length ? B64.charAt(b2 & 63) : "=";
  }
  return out;
}
function b64decode(str) {
  str = String(str || "").replace(/[^A-Za-z0-9+\/]/g, "");
  var bytes = [], i, n, c0, c1, c2, c3;
  for (i = 0; i < str.length; i += 4) {
    c0 = B64.indexOf(str.charAt(i));
    c1 = B64.indexOf(str.charAt(i + 1));
    c2 = i + 2 < str.length ? B64.indexOf(str.charAt(i + 2)) : -1;
    c3 = i + 3 < str.length ? B64.indexOf(str.charAt(i + 3)) : -1;
    n = (c0 << 18) | (c1 << 12) | ((c2 < 0 ? 0 : c2) << 6) | (c3 < 0 ? 0 : c3);
    bytes.push((n >> 16) & 255);
    if (c2 >= 0) bytes.push((n >> 8) & 255);
    if (c3 >= 0) bytes.push(n & 255);
  }
  return bytes;
}
function utf8encode(str) {
  var s, out = [], i, c;
  try { s = unescape(encodeURIComponent(String(str))); } catch (e) { s = String(str); }
  for (i = 0; i < s.length; i++) {
    c = s.charCodeAt(i);
    if (c < 128) out.push(c);
    else if (c < 2048) {
      out.push(192 | (c >> 6));
      out.push(128 | (c & 63));
    } else {
      out.push(224 | (c >> 12));
      out.push(128 | ((c >> 6) & 63));
      out.push(128 | (c & 63));
    }
  }
  return out;
}
function utf8decode(bytes) {
  var s = "", i, c;
  for (i = 0; i < bytes.length; i++) {
    c = bytes[i];
    if (c < 128) s += String.fromCharCode(c);
    else if (c < 224 && i + 1 < bytes.length) {
      s += String.fromCharCode(((c & 31) << 6) | (bytes[++i] & 63));
    } else if (i + 2 < bytes.length) {
      s += String.fromCharCode(((c & 15) << 12) | ((bytes[++i] & 63) << 6) | (bytes[++i] & 63));
    }
  }
  try { return decodeURIComponent(escape(s)); } catch (e) { return s; }
}
function hexOf(buf) {
  var out = "", i, h;
  for (i = 0; i < buf.bytes.length; i++) {
    h = buf.bytes[i].toString(16);
    out += h.length < 2 ? "0" + h : h;
  }
  return out;
}
function bytesOf(value, enc) {
  if (value == null) return [];
  if (value && value.bytes) return value.bytes.slice();
  if (Object.prototype.toString.call(value) === "[object Array]") return value.slice();
  if (value.buffer && value.byteLength != null) {
    var a = [], i;
    for (i = 0; i < value.byteLength; i++) a.push(value[i] & 255);
    return a;
  }
  var s = String(value);
  enc = (enc || "utf8").toLowerCase();
  if (enc === "base64") return b64decode(s);
  if (enc === "hex") {
    var out = [], j;
    for (j = 0; j < s.length; j += 2) out.push(parseInt(s.substr(j, 2), 16) || 0);
    return out;
  }
  if (enc === "binary" || enc === "latin1") {
    var b = [], k;
    for (k = 0; k < s.length; k++) b.push(s.charCodeAt(k) & 255);
    return b;
  }
  return utf8encode(s);
}
function Buf(bytes) {
  this.bytes = bytes || [];
  this.length = this.bytes.length;
}
Buf.prototype.toString = function (enc) {
  enc = (enc || "utf8").toLowerCase();
  if (enc === "base64") return b64encode(this.bytes);
  if (enc === "hex") {
    var out = "", i, h;
    for (i = 0; i < this.bytes.length; i++) {
      h = (this.bytes[i] & 255).toString(16);
      out += h.length < 2 ? "0" + h : h;
    }
    return out;
  }
  if (enc === "binary" || enc === "latin1") {
    var s = "", j;
    for (j = 0; j < this.bytes.length; j++) s += String.fromCharCode(this.bytes[j] & 255);
    return s;
  }
  return utf8decode(this.bytes);
};
Buf.prototype.slice = function (a, b) {
  return new Buf(this.bytes.slice(a, b));
};
Buf.prototype.toJSON = function () {
  return { type: "Buffer", data: this.bytes };
};
function Buffer(value, enc, len) { return Buffer.from(value, enc, len); }
Buffer.from = function (value, enc, len) {
  var b = bytesOf(value, enc);
  if (len != null) b = b.slice(0, len);
  return new Buf(b);
};
Buffer.alloc = function (n) {
  var a = [], i;
  for (i = 0; i < n; i++) a.push(0);
  return new Buf(a);
};
Buffer.concat = function (list) {
  var out = [], i, j;
  for (i = 0; i < list.length; i++) {
    var b = bytesOf(list[i]);
    for (j = 0; j < b.length; j++) out.push(b[j]);
  }
  return new Buf(out);
};
Buffer.byteLength = function (value, enc) {
  return bytesOf(value, enc).length;
};
Buffer.isBuffer = function (x) { return !!(x && x.bytes); };

var fsStore = {};
var fs = {
  readFileSync: function (p, enc) {
    p = String(p);
    if (/seeds-fallback\.json$/.test(p)) return __seedsFallback || '{"seeds":[]}';
    if (fsStore[p] == null) throw new Error("ENOENT: " + p);
    return fsStore[p];
  },
  writeFileSync: function (p, data) { fsStore[String(p)] = String(data); },
  unlinkSync: function (p) { delete fsStore[String(p)]; },
  existsSync: function (p) {
    p = String(p);
    return /seeds-fallback\.json$/.test(p) || fsStore[p] != null;
  },
  mkdirSync: function () {}
};
var path = {
  join: function () {
    var parts = [], i;
    for (i = 0; i < arguments.length; i++) {
      if (arguments[i] != null && String(arguments[i]) !== "") parts.push(String(arguments[i]));
    }
    return parts.join("/").replace(/\/+/g, "/");
  },
  dirname: function (p) {
    p = String(p || "");
    var i = p.lastIndexOf("/");
    return i <= 0 ? "." : p.slice(0, i);
  },
  basename: function (p) {
    p = String(p || "");
    var i = p.lastIndexOf("/");
    return i < 0 ? p : p.slice(i + 1);
  }
};

function urlParse(s) {
  s = String(s || "");
  var m = /^(https?:)\/\/([^\/:]+)(?::(\d+))?([^?#]*)?(\?[^#]*)?/.exec(s);
  if (!m) return { href: s, protocol: "", hostname: "", port: null, path: "/", search: "", query: "" };
  return {
    href: s,
    protocol: m[1],
    hostname: m[2],
    port: m[3] || null,
    path: (m[4] || "/") + (m[5] || ""),
    search: m[5] || "",
    query: (m[5] || "").replace(/^\?/, "")
  };
}
var url = {
  parse: urlParse,
  resolve: function (base, rel) {
    if (/^https?:/i.test(rel)) return rel;
    var b = urlParse(base);
    if (String(rel).charAt(0) === "/") {
      return b.protocol + "//" + b.hostname + (b.port ? ":" + b.port : "") + rel;
    }
    var dir = b.path.replace(/[^\/]*$/, "");
    return b.protocol + "//" + b.hostname + (b.port ? ":" + b.port : "") + dir + rel;
  }
};

var dnsx = { prepare: function (opts, cb) { cb(null, opts); } };
var upstream = { agentFor: function () { return undefined; }, describe: function () { return null; } };

var httpSeq = 1;
var pendingHttp = {};
var pendingTimers = {};

function EventEmitter() { this._ev = {}; }
EventEmitter.prototype.on = function (name, fn) {
  (this._ev[name] = this._ev[name] || []).push(fn);
  return this;
};
EventEmitter.prototype.emit = function (name) {
  var args = Array.prototype.slice.call(arguments, 1);
  var list = (this._ev[name] || []).slice();
  for (var i = 0; i < list.length; i++) {
    try { list[i].apply(this, args); } catch (e) { __nativeLog("emit " + name + ": " + e); }
  }
};

function cleanHeaders(h) {
  var out = {};
  if (!h) return out;
  for (var k in h) {
    if (Object.prototype.hasOwnProperty.call(h, k) && h[k] != null) out[k] = String(h[k]);
  }
  return out;
}
function buildUrl(o) {
  if (o && o.href) return o.href;
  o = o || {};
  var proto = o.protocol || "https:";
  var host = o.hostname || o.host || "";
  var port = o.port ? ":" + o.port : "";
  var p = o.path || "/";
  return proto + "//" + host + port + p;
}
function request(options, cb) {
  if (typeof options === "string") options = urlParse(options);
  var req = new EventEmitter();
  var id = httpSeq++;
  req._id = id;
  req._writes = [];
  pendingHttp[id] = { req: req, cb: cb };
  req.setTimeout = function (ms, fn) {
    if (fn) req.on("timeout", fn);
    req._timer = setTimeout(function () {
      if (pendingHttp[id]) {
        req.emit("timeout");
        req.abort();
      }
    }, ms || 20000);
    return req;
  };
  req.write = function (chunk) {
    if (chunk != null) req._writes.push(bytesOf(chunk));
    return true;
  };
  req.end = function (chunk) {
    if (chunk != null) req._writes.push(bytesOf(chunk));
    var all = [];
    for (var i = 0; i < req._writes.length; i++) {
      for (var j = 0; j < req._writes[i].length; j++) all.push(req._writes[i][j]);
    }
    var opts = {
      url: buildUrl(options),
      method: options.method || (all.length ? "POST" : "GET"),
      headers: cleanHeaders(options.headers),
      timeout: 25000
    };
    __nativeHTTP(JSON.stringify(opts), b64encode(all), String(id));
  };
  req.abort = function () {
    if (pendingHttp[id]) {
      delete pendingHttp[id];
      if (req._timer) clearTimeout(req._timer);
      __nativeAbort(String(id));
    }
  };
  return req;
}
var https = {
  request: request,
  get: function (options, cb) {
    var r = request(options, cb);
    r.end();
    return r;
  }
};
var http = https;

function __httpDone(id, status, headersJSON, bodyB64) {
  var p = pendingHttp[id];
  if (!p) return;
  delete pendingHttp[id];
  if (p.req._timer) clearTimeout(p.req._timer);
  if (status < 0) {
    p.req.emit("error", new Error("network error"));
    p.req.emit("close");
    return;
  }
  var res = new EventEmitter();
  res.statusCode = status;
  res.headers = {};
  try { res.headers = JSON.parse(headersJSON || "{}"); } catch (e) {}
  res.resume = function () {};
  res.destroy = function () {};
  if (p.cb) p.cb(res);
  var body = new Buf(b64decode(bodyB64 || ""));
  if (body.length) res.emit("data", body);
  res.emit("end");
  p.req.emit("close");
}

var crypto = {
  createCipheriv: function (alg, key, iv) {
    var chunks = [];
    return {
      update: function (data) { chunks.push(bytesOf(data)); return new Buf([]); },
      final: function () {
        var all = [], i, j;
        for (i = 0; i < chunks.length; i++) for (j = 0; j < chunks[i].length; j++) all.push(chunks[i][j]);
        var out = __native3DES(b64encode(all), hexOf(new Buf(bytesOf(key))), 1);
        return new Buf(b64decode(out));
      },
      setAutoPadding: function () {}
    };
  },
  createDecipheriv: function (alg, key, iv) {
    var chunks = [];
    return {
      update: function (data) { chunks.push(bytesOf(data)); return new Buf([]); },
      final: function () {
        var all = [], i, j;
        for (i = 0; i < chunks.length; i++) for (j = 0; j < chunks[i].length; j++) all.push(chunks[i][j]);
        var out = __native3DES(b64encode(all), hexOf(new Buf(bytesOf(key))), 0);
        return new Buf(b64decode(out));
      },
      setAutoPadding: function () {}
    };
  },
  randomBytes: function (n) {
    return new Buf(b64decode(__nativeRandom(n)));
  },
  createHash: function (alg) {
    var chunks = [];
    return {
      update: function (data) {
        chunks.push(bytesOf(data));
        return this;
      },
      digest: function (enc) {
        var all = [], i, j;
        for (i = 0; i < chunks.length; i++) {
          for (j = 0; j < chunks[i].length; j++) all.push(chunks[i][j]);
        }
        var out = __nativeDigest(b64encode(all), String(alg || "md5").toLowerCase());
        var buf = new Buf(b64decode(out));
        return enc === "hex" ? buf.toString("hex") : buf;
      }
    };
  }
};

function require(name) {
  if (name === "crypto") return crypto;
  if (name === "https") return https;
  if (name === "http") return http;
  if (name === "fs") return fs;
  if (name === "url") return url;
  if (name === "path") return path;
  if (name === "./dnsx") return dnsx;
  if (name === "./upstream") return upstream;
  return {};
}

var process = { version: "v0.12.0", platform: "ios", arch: "armv7", env: {} };
var console = {
  log: function (m) { __nativeLog(String(m)); },
  error: function (m) { __nativeLog("ERR " + String(m)); },
  warn: function (m) { __nativeLog("WARN " + String(m)); }
};

function setTimeout(fn, ms) {
  var id = httpSeq++;
  pendingTimers[id] = fn;
  __nativeTimer(ms || 0, String(id));
  return id;
}
function clearTimeout(id) {
  delete pendingTimers[id];
  __nativeCancelTimer(String(id));
}
function setInterval(fn, ms) {
  function tick() { fn(); setTimeout(tick, ms); }
  return setTimeout(tick, ms);
}
function __timerFire(id) {
  var fn = pendingTimers[id];
  delete pendingTimers[id];
  if (fn) {
    try { fn(); } catch (e) { __nativeLog("timer: " + e); }
  }
}

function __serviceInvoke(method, paramsJSON, token) {
  var params;
  try { params = JSON.parse(paramsJSON || "{}"); } catch (e) { params = {}; }
  var sent = false;
  function done(err, data) {
    if (sent) return;
    sent = true;
    var errText = err ? String((err && err.message) || err) : "";
    __deliver(token, errText, JSON.stringify(data == null ? null : data));
  }
  try {
    var m = module.exports;
    if (method === "home") m.home(params.root || "movies", params.pageNum || 1, done);
    else if (method === "search") m.search(params.value || "", params.pageNum || 1, done);
    else if (method === "detail") m.detail(params.contentId, done);
    else if (method === "resolve") m.resolve(params.contentId, params.seriesContentId, params, done);
    else if (method === "mediaInfo") m.mediaInfo(params.contentId, params.seriesContentId, done);
    else if (method === "fetchM3u") m.fetchM3u(params.url, done);
    else if (method === "ping") done(null, { pong: true });
    else if (method === "abortMedia") done(null, { ok: true });
    else if (method === "prewarm") done(null, { ok: true });
    else if (method === "liveChannels") done(null, { channels: [] });
    else if (method === "liveCategories") done(null, { categories: [] });
    else if (method === "resolveLive") done(new Error("TV en vivo no soportada en esta version"));
    else done(null, {});
  } catch (e) {
    done(e);
  }
}

function __seedsFallbackSet(json) { __seedsFallback = json; }
function __magisLoaded() {
  var m = module.exports;
  return !!(m && m.home && m.search && m.detail && m.resolve);
}