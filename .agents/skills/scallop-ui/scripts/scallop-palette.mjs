// scallop palette engine, rebuilt from the Scallop spec appendix
// usage: node scallop-palette.mjs "#RRGGBB" [--write [dir]]
import { writeFileSync, mkdirSync } from "node:fs"
import { join } from "node:path"
import { Hct, argbFromHex, hexFromArgb, TonalPalette } from "@material/material-color-utilities"
import { wcagContrast, differenceCiede2000, filterDeficiencyProt, filterDeficiencyDeuter, filterDeficiencyTrit } from "culori"

const args = process.argv.slice(2)
const seedHex = args.find(a => /^#?[0-9a-f]{6}$/i.test(a))
if (!seedHex) {
  console.error('usage: node scallop-palette.mjs "#RRGGBB" [--write [dir]]')
  process.exit(2)
}
const wi = args.indexOf("--write")
const writeDir = wi >= 0 ? (args[wi + 1] && !args[wi + 1].startsWith("-") ? args[wi + 1] : ".") : null

const seed = Hct.fromInt(argbFromHex(seedHex.startsWith("#") ? seedHex : "#" + seedHex))
const H = seed.hue
const hx = argb => hexFromArgb(argb).toLowerCase()
const mk = (h, c, t) => hx(Hct.from(((h % 360) + 360) % 360, c, t).toInt())
const fails = []
const warns = []
const gate = (ok, msg) => { console.log("  %s  %s", ok ? "pass" : "FAIL", msg); if (!ok) fails.push(msg) }
const warn = msg => { console.log("  warn  %s", msg); warns.push(msg) }

console.log("seed %s  hue %s  chroma %s  tone %s", seedHex, H.toFixed(1), seed.chroma.toFixed(1), seed.tone.toFixed(1))
if (seed.chroma < 5) {
  console.error("FAIL seed chroma %s < 5, hue is noise", seed.chroma.toFixed(1))
  process.exit(1)
}

// --- palettes and tones ---
const P = { primary: [H, 36], secondary: [H, 16], tertiary: [H + 60, 24], neutral: [H, 6], nv: [H, 8], error: [25, 84] }
const T = {
  primary: ["primary", [80, 40]], "on-primary": ["primary", [20, 100]], "primary-container": ["primary", [30, 90]], "on-primary-container": ["primary", [90, 30]],
  secondary: ["secondary", [80, 40]], "on-secondary": ["secondary", [20, 100]], "secondary-container": ["secondary", [30, 90]], "on-secondary-container": ["secondary", [90, 30]],
  tertiary: ["tertiary", [80, 40]], "on-tertiary": ["tertiary", [20, 100]], "tertiary-container": ["tertiary", [30, 90]], "on-tertiary-container": ["tertiary", [90, 30]],
  "surface-lowest": ["neutral", [4, 100]], surface: ["neutral", [6, 98]], "surface-container-low": ["neutral", [10, 96]], "surface-container": ["neutral", [12, 94]],
  "surface-container-high": ["neutral", [17, 92]], "surface-container-highest": ["neutral", [22, 90]], "on-surface": ["neutral", [90, 10]],
  "on-surface-variant": ["nv", [80, 30]], outline: ["nv", [60, 50]], "outline-variant": ["nv", [30, 80]], error: ["error", [80, 40]],
}
const roles = { dark: {}, light: {} }
for (const [name, [pal, [d, l]]] of Object.entries(T)) {
  roles.dark[name] = mk(...P[pal], d)
  roles.light[name] = mk(...P[pal], l)
}

// --- status: anchor hue nudged 10% toward the seed, chroma fixed, tones pinned ---
const nudge = a => {
  let d = ((H - a + 540) % 360) - 180
  return (a + 0.1 * d + 360) % 360
}
const ST = { ok: [152, 53], bad: [23, 42], warn: [74, 44] }
const stTones = {
  ok: { dark: 78, light: 54, textDark: 78, textLight: 40 },
  bad: { dark: 62, light: 30, textDark: 62, textLight: 30 },
  warn: { dark: 90, light: 44, textDark: 90, textLight: 44 },
}
const lin = h => h
const sim = {
  normal: x => x,
  protan: filterDeficiencyProt(1),
  deutan: filterDeficiencyDeuter(1),
  tritan: filterDeficiencyTrit(1),
}
const de = differenceCiede2000()
const minCvd = (set) => {
  let worst = { v: Infinity, what: "" }
  const names = Object.keys(set)
  for (const [sn, f] of Object.entries(sim)) {
    for (let i = 0; i < names.length; i++) for (let j = i + 1; j < names.length; j++) {
      const v = de(f(set[names[i]]), f(set[names[j]]))
      if (v < worst.v) worst = { v, what: `${names[i]}/${names[j]} ${sn}` }
    }
  }
  return worst
}
const statusFor = (mode, warnDark) => {
  const out = {}
  for (const k of Object.keys(ST)) {
    const [a, c] = ST[k]
    const h = nudge(a)
    let tm = mode === "dark" ? stTones[k].dark : stTones[k].light
    let tt = mode === "dark" ? stTones[k].textDark : stTones[k].textLight
    if (k === "warn" && mode === "dark") { tm = warnDark; tt = warnDark }
    out[k] = { mark: mk(h, c, tm), text: mk(h, c, tt), h, c }
  }
  return out
}
let warnDark = 90
let status = { dark: statusFor("dark", warnDark), light: statusFor("light") }
while (minCvd(Object.fromEntries(Object.entries(status.dark).map(([k, v]) => [k, v.mark]))).v < 8 && warnDark < 94) {
  warnDark += 1
  status.dark = statusFor("dark", warnDark)
}
const stC = (mode) => ({ container: mk(...[0, 0], 0), mode })
for (const mode of ["dark", "light"]) {
  for (const k of Object.keys(ST)) {
    const [a, c] = ST[k]
    const h = nudge(a)
    status[mode][k].container = mk(h, c, mode === "dark" ? 30 : 90)
    status[mode][k].onContainer = mk(h, c, mode === "dark" ? 90 : 10)
  }
}

// --- categorical, fixed ---
const CAT = { "cat-1": ["#4392c9", "#2a7cbc"], "cat-2": ["#7b5db0", "#694b92"], "cat-3": ["#b45827", "#973e08"], "cat-4": ["#6a9844", "#527e2b"] }

// --- gates ---
for (const mode of ["dark", "light"]) {
  const r = roles[mode]
  const S = status[mode]
  console.log("\n[%s]", mode)
  for (const bg of ["surface-container-low", "surface-container-high"]) {
    gate(wcagContrast(r["on-surface"], r[bg]) >= 4.5, `on-surface on ${bg} >= 4.5 (${wcagContrast(r["on-surface"], r[bg]).toFixed(2)})`)
    gate(wcagContrast(r["on-surface-variant"], r[bg]) >= 4.5, `on-surface-variant on ${bg} >= 4.5 (${wcagContrast(r["on-surface-variant"], r[bg]).toFixed(2)})`)
    gate(wcagContrast(r.primary, r[bg]) >= 4.5, `primary on ${bg} >= 4.5 (${wcagContrast(r.primary, r[bg]).toFixed(2)})`)
    for (const k of Object.keys(ST)) {
      gate(wcagContrast(S[k].mark, r[bg]) >= 3, `${k} mark on ${bg} >= 3 (${wcagContrast(S[k].mark, r[bg]).toFixed(2)})`)
      gate(wcagContrast(S[k].text, r[bg]) >= 4.5, `${k} text on ${bg} >= 4.5 (${wcagContrast(S[k].text, r[bg]).toFixed(2)})`)
    }
    if (bg === "surface-container-low") for (const [k, [d, l]] of Object.entries(CAT)) {
      const c = mode === "dark" ? d : l
      gate(wcagContrast(c, r[bg]) >= 3, `${k} on ${bg} >= 3 (${wcagContrast(c, r[bg]).toFixed(2)})`)
    }
  }
  gate(wcagContrast(r["on-primary"], r.primary) >= 4.5, `on-primary on primary >= 4.5`)
  gate(wcagContrast(r["on-primary-container"], r["primary-container"]) >= 4.5, `on-primary-container on primary-container >= 4.5`)
  const w = minCvd(Object.fromEntries(Object.keys(ST).map(k => [k, S[k].mark])))
  gate(w.v >= 8, `status marks CVD floor >= 8.0, worst ${w.v.toFixed(1)} (${w.what})`)
  for (const [k, [d, l]] of Object.entries(CAT)) {
    const v = de(mode === "dark" ? d : l, r.primary)
    if (v < 10.9) warn(`${k} is within dE ${v.toFixed(1)} of primary, never show them side by side in one chart`)
  }
}
const lp = Hct.fromInt(argbFromHex(roles.light.primary))
if (lp.hue >= 90 && lp.hue <= 111 && lp.chroma > 16 && lp.tone < 65) warn("light primary lands in the DislikeAnalyzer band (hue 90 to 111), reads olive, check by eye")
if (warnDark > 90) warn(`dark warn tone raised to ${warnDark} to pass the CVD gate`)

console.log("\n%s, %d fail, %d warn", fails.length ? "FAILED" : "all gates pass", fails.length, warns.length)

// --- output ---
const flat = mode => ({
  ...roles[mode],
  ok: status[mode].ok.mark, "ok-text": status[mode].ok.text, bad: status[mode].bad.mark, "bad-text": status[mode].bad.text,
  warn: status[mode].warn.mark, "warn-text": status[mode].warn.text,
  ...Object.fromEntries(Object.keys(ST).flatMap(k => [[`${k}-container`, status[mode][k].container], [`on-${k}-container`, status[mode][k].onContainer]])),
  ...Object.fromEntries(Object.entries(CAT).map(([k, [d, l]]) => [k, mode === "dark" ? d : l])),
})
if (writeDir !== null && !fails.length) {
  mkdirSync(writeDir, { recursive: true })
  const block = m => Object.entries(flat(m)).map(([k, v]) => `  --${k}: ${v};`).join("\n")
  const css = `/* generated by scallop-palette.mjs, seed ${seedHex}, do not edit */\n:root {\n  color-scheme: dark;\n${block("dark")}\n}\n:root[data-theme="light"] {\n  color-scheme: light;\n${block("light")}\n}\n@media (prefers-color-scheme: light) {\n  :root:not([data-theme="dark"]) {\n    color-scheme: light;\n${block("light").replace(/^/gm, "  ")}\n  }\n}\n`
  const dtcg = m => Object.fromEntries(Object.entries(flat(m)).map(([k, v]) => {
    const n = parseInt(v.slice(1), 16)
    return [k, { $type: "color", $value: { colorSpace: "srgb", components: [(n >> 16 & 255) / 255, (n >> 8 & 255) / 255, (n & 255) / 255], hex: v } }]
  }))
  writeFileSync(join(writeDir, "tokens.css"), css)
  writeFileSync(join(writeDir, "tokens.json"), JSON.stringify({ $description: `scallop seed ${seedHex}`, dark: dtcg("dark"), light: dtcg("light") }, null, 2))
  console.log("wrote tokens.css and tokens.json to %s", writeDir)
} else if (writeDir !== null) console.log("not writing, gates failed")
process.exit(fails.length ? 1 : 0)
