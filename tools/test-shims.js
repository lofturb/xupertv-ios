"use strict";
/* Prueba local (Node) de Resources/service/shims.js + magis.js.
 * Reproduce los puentes nativos con crypto/https de Node para validar
 * 3DES, Buffer, timers y el flujo del portal antes de compilar el IPA.
 */
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const crypto = require("crypto");
const http = require("http");
const https = require("https");

const root = path.resolve(__dirname, "..");
const shims = fs.readFileSync(path.join(root, "Resources", "service", "shims.js"), "utf8");
const magis = fs.readFileSync(path.join(root, "Resources", "service", "magis.js"), "utf8");
const fallback = fs.readFileSync(path.join(root, "Resources", "service", "seeds-fallback.json"), "utf8");

let finished = false;
const timers = {};

const sandbox = {
  __native3DES: function (b64, keyHex, encrypt) {
    const key = Buffer.from(keyHex, "hex");
    const input = Buffer.from(b64, "base64");
    try {
      if (encrypt) {
        const c = crypto.createCipheriv("des-ede3", key, Buffer.alloc(0));
        return Buffer.concat([c.update(input), c.final()]).toString("base64");
      }
      const d = crypto.createDecipheriv("des-ede3", key, Buffer.alloc(0));
      return Buffer.concat([d.update(input), d.final()]).toString("base64");
    } catch (e) {
      console.log("3DES ERR", e.message);
      return "";
    }
  },
  __nativeHTTP: function (optsJSON, bodyB64, id) {
    const o = JSON.parse(optsJSON);
    const body = Buffer.from(bodyB64 || "", "base64");
    const go = (urlStr, redirects) => {
      let u;
      try { u = new URL(urlStr); } catch (e) {
        sandbox.__httpDone(Number(id), -1, "{}", "");
        return;
      }
      const lib = u.protocol === "http:" ? http : https;
      const req = lib.request({
        hostname: u.hostname,
        port: u.port || undefined,
        path: u.pathname + u.search,
        method: o.method || "GET",
        headers: o.headers || {},
        rejectUnauthorized: false
      }, (res) => {
        if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location && redirects < 5) {
          res.resume();
          return go(new URL(res.headers.location, urlStr).toString(), redirects + 1);
        }
        const chunks = [];
        res.on("data", (d) => chunks.push(d));
        res.on("end", () => {
          sandbox.__httpDone(Number(id), res.statusCode, JSON.stringify(res.headers), Buffer.concat(chunks).toString("base64"));
        });
        res.on("error", () => sandbox.__httpDone(Number(id), -1, "{}", ""));
      });
      req.on("error", () => sandbox.__httpDone(Number(id), -1, "{}", ""));
      req.setTimeout(o.timeout || 25000, () => { req.destroy(); sandbox.__httpDone(Number(id), -1, "{}", ""); });
      if (body.length) req.write(body);
      req.end();
    };
    go(o.url, 0);
  },
  __nativeAbort: function () {},
  __nativeTimer: function (ms, id) {
    timers[id] = setTimeout(function () { sandbox.__timerFire(String(id)); }, ms);
  },
  __nativeCancelTimer: function (id) {
    if (timers[id]) clearTimeout(timers[id]);
    delete timers[id];
  },
  __nativeRandom: function (n) { return crypto.randomBytes(n).toString("base64"); },
  __nativeDigest: function (b64, alg) {
    return crypto.createHash(alg || "md5").update(Buffer.from(b64, "base64")).digest("base64");
  },
  __nativeLog: function (m) { console.log("[js]", m); },
  __deliver: function (token, err, data) {
    if (finished) return;
    finished = true;
    console.log("DELIVER", token, "ERR=" + err);
    console.log("DATA", String(data).slice(0, 1200));
    process.exit(err ? 2 : 0);
  },
  Buffer: Buffer,
  process: process,
  console: console,
  setTimeout: setTimeout,
  clearTimeout: clearTimeout,
  setInterval: setInterval,
  clearInterval: clearInterval,
  escape: escape,
  unescape: unescape,
  encodeURIComponent: encodeURIComponent,
  decodeURIComponent: decodeURIComponent
};
sandbox.global = sandbox;
vm.createContext(sandbox);

vm.runInContext(shims, sandbox, { filename: "shims.js" });
vm.runInContext("__seedsFallbackSet(" + JSON.stringify(fallback) + ");", sandbox, { filename: "fallback.js" });
vm.runInContext(magis, sandbox, { filename: "magis.js" });
console.log("LOADED", vm.runInContext("__magisLoaded()", sandbox));

const method = process.argv[2] || "search";
const params = process.argv[3] || JSON.stringify({ value: "how i met your mother", pageNum: 1 });
console.log("CALL", method, params);
if (method === "rawsearch") {
  const code = "(function(){var m=module.exports;m.ensureSession(function(e){if(e)return __deliver(1,String(e)||'session','');m.call('v3/searchByName',{value:'how i met your mother',type:'1',columnId:'',filter:'',pageNum:1,pageSize:50},function(err,res){__deliver(1,err?String(err):'',JSON.stringify(res||null));});});})()";
  vm.runInContext(code, sandbox);
} else if (method === "debugsearch") {
  const code = "(function(){var m=module.exports;var old=m.search;m.search=function(v,p,cb){console.log('search args '+v+' '+p);old(v,p,function(e,r){console.log('search cb err='+e+' data='+JSON.stringify(r).slice(0,400));cb(e,r);});};__serviceInvoke('search',JSON.stringify({value:'how i met your mother',pageNum:1}),1);})()";
  vm.runInContext(code, sandbox);
} else if (method === "detailtest") {
  const code = "(function(){var m=module.exports;m.detail('405C67D1F2B01EAD9506FE82AD86BFDC',function(e,d){if(e)return __deliver(1,String(e),'');var out={title:d.item&&d.item.title,itemId:d.item&&d.item.id,seasons:(d.seasons||[]).length,episodes:(d.episodes||[]).slice(0,3)};__deliver(1,'',JSON.stringify(out));});})()";
  vm.runInContext(code, sandbox);
} else if (method === "resolvetest") {
  const code = "(function(){var m=module.exports;var p={contentId:'609E20053A2F48EAA49806DB97950C74',seriesContentId:'405C67D1F2B01EAD9506FE82AD86BFDC',quality:'720',hevc:false,uhd:false,trackIndex:0,audioPreference:'es-lat',audioTrack:0};m.resolve(p.contentId,p.seriesContentId,p,function(e,d){if(e)return __deliver(1,String(e),'');var out={url:d.url,mime:d.mime,duration:d.duration,audio:d.audio,codec:d.codec,headers:Object.keys(d.headers||{}),subtitles:(d.subtitles||[]).length,tracks:(d.availableTracks||[]).length};__deliver(1,'',JSON.stringify(out));});})()";
  vm.runInContext(code, sandbox);
} else if (method === "qualities") {
  const code = "(function(){var m=module.exports;var qs=['auto','720','480','1080'];var out=[];var i=0;function next(){if(i>=qs.length)return __deliver(1,'',JSON.stringify(out));var q=qs[i++];var p={contentId:'609E20053A2F48EAA49806DB97950C74',seriesContentId:'405C67D1F2B01EAD9506FE82AD86BFDC',quality:q,hevc:false,uhd:false,trackIndex:0,audioPreference:'es-lat',audioTrack:0};m.resolve(p.contentId,p.seriesContentId,p,function(e,d){out.push({q:q,err:e?String(e.message||e):'',codec:d&&d.codec,quality:d&&d.quality,dur:d&&d.duration,audio:d&&d.audio,selected:d&&d.selectedTrack,tracks:(d&&d.availableTracks||[]).map(function(x){return {q:x.quality,h:x.height,b:x.bitrateKbps,f:x.format};})});next();});}next();})()";
  vm.runInContext(code, sandbox);
} else if (method === "codecprobe") {
  const code = "(function(){var m=module.exports;var terms=String(process.env.XUPER_TERMS||'spiderman,avatar,naruto,batman,dragon ball').split(',');var out=[];var i=0;function next(){if(i>=terms.length){__deliver(1,'',JSON.stringify(out));return;}var q=terms[i++];m.search(q,1,function(e,r){var it=r&&r.items&&r.items[0];if(!it){out.push({q:q,err:'sin resultados'});return next();}m.detail(it.id,function(e2,d){var ep=(d&&d.episodes&&d.episodes[0])||{id:it.id};var p={quality:'auto',hevc:false,uhd:false,trackIndex:0,audioPreference:'es-lat',audioTrack:0};m.resolve(ep.id,it.id,p,function(e3,s){out.push({q:q,title:it.title,ep:ep.title,err:e3?String(e3.message||e3):'',codec:s&&s.codec,quality:s&&s.quality,audio:s&&s.audio,dur:s&&s.duration,tracks:(s&&s.availableTracks||[]).length});next();});});});}next();})()";
  vm.runInContext(code, sandbox);
} else if (method === "searchprobe") {
  const code = "(function(){var m=module.exports;var qs=String(process.env.XUPER_TERMS||'').split(',').filter(function(x){return x.length>0});var out=[];var i=0;function next(){if(i>=qs.length){__deliver(1,'',JSON.stringify(out));return;}var q=qs[i++];m.search(q,1,function(e,r){var its=(r&&r.items)||[];var first=null;if(its.length){first={id:its[0].id,title:its[0].title,kind:its[0].kind}}out.push({q:q,n:its.length,total:r&&r.total,err:e?String(e.message||e):'',first:first});next();});}next();})()";
  vm.runInContext(code, sandbox);
} else if (method === "codectitle") {
  const code = "(function(){var m=module.exports;var id=process.env.XUPER_ID;var title=process.env.XUPER_TITLE||id;m.detail(id,function(e2,d){if(e2)return __deliver(1,'',JSON.stringify({t:title,id:id,err:String(e2.message||e2)}));var eps=(d&&d.episodes)||[];var out=[];var i=0;function next(){if(i>=Math.min(eps.length,3))return __deliver(1,'',JSON.stringify({t:title,id:id,seasons:(d.seasons||[]).length,eps:out}));var ep=eps[i++];var p={quality:'auto',hevc:false,uhd:false,trackIndex:0,audioPreference:'es-lat',audioTrack:0};m.resolve(ep.id,id,p,function(e3,s){out.push({ep:ep.title,err:e3?String(e3.message||e3):'',codec:s&&s.codec,quality:s&&s.quality,audio:s&&s.audio,tracks:(s&&s.availableTracks||[]).length});next();});}next();});})()";
  vm.runInContext(code, sandbox);
} else {
  vm.runInContext("__serviceInvoke(" + JSON.stringify(method) + ", " + JSON.stringify(params) + ", 1);", sandbox);
}

setTimeout(() => {
  if (!finished) {
    console.log("TIMEOUT");
    process.exit(3);
  }
}, 90000);