// One-time conversion: GJS glyphData.js → bar/glyphData.json (plan Phase 4).
// The GJS module ends with `var GlyphData = {...}` and no CommonJS export,
// so we eval it in a module sandbox and serialize the object.
//
// Usage: node convert-glyphdata.js [src.js] [out.json]
const fs = require("fs");
const path = require("path");

const src = process.argv[2]
    || "/home/king/.hyprcandy/GJS/hyprcandydock/glyphData.js";
const out = process.argv[3]
    || path.join(__dirname, "..", "glyphData.json");

const code = fs.readFileSync(src, "utf8") + "\n;module.exports = GlyphData;";
const mod = new module.constructor();
mod._compile(code, src);
const data = mod.exports;

if (!data || !Array.isArray(data.EMOJI_ALL)
    || !Array.isArray(data.EMOJI_GROUPS) || !Array.isArray(data.NERD_CATS)) {
    console.error("unexpected glyphData shape");
    process.exit(1);
}

fs.writeFileSync(out, JSON.stringify(data));
const nerd = data.NERD_CATS.reduce((n, c) => n + c.glyphs.length, 0);
console.log(`wrote ${out}: ${data.EMOJI_ALL.length} emojis, `
    + `${data.EMOJI_GROUPS.length} emoji groups, `
    + `${data.NERD_CATS.length} nerd cats (${nerd} glyphs)`);
