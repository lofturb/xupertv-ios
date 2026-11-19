"use strict";
/* Busca tokens basura (CJK, emoji, palabras sueltas inglesas que no tienen
 * sentido en el c\u00f3digo) en los fuentes del port. */
const fs = require("fs");
const path = require("path");
const root = __dirname;
const exts = [".m", ".h", ".js", ".html", ".css", ".plist", ".md"];
const skipDirs = ["vendor", "node_modules", "dist", "assets"];
const junk = /\b(Upon|Tornado|Hank|oun|othes|Ol|Olsen|Now|nown|Sor|which|Korea|capit|Ste|West|firstly|lastly|belt|rooted|deserted|Heat|Juice|prevent|mention|asked|粉末|分享)\b/;
function walk(dir) {
  for (const name of fs.readdirSync(dir)) {
    const full = path.join(dir, name);
    const stat = fs.statSync(full);
    if (stat.isDirectory()) {
      if (skipDirs.includes(name)) continue;
      walk(full);
    } else if (exts.includes(path.extname(name))) {
      const text = fs.readFileSync(full, "utf8");
      text.split("\n").forEach((line, i) => {
        if (/[\u4e00-\u9fff]/.test(line) || junk.test(line)) {
          console.log(full.replace(root, ".") + ":" + (i + 1) + " " + line.trim().slice(0, 90));
        }
      });
    }
  }
}
walk(root);
console.log("fin");

