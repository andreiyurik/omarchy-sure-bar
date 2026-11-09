// Run with: node tests/project.test.js
// Guards the rules that a reviewer would otherwise have to check by hand.
const fs = require("fs"), path = require("path"), assert = require("assert")
const root = path.join(__dirname, "..")
const read = file => fs.readFileSync(path.join(root, file), "utf8")
const qml = fs.readdirSync(root).filter(file => file.endsWith(".qml"))
const en = JSON.parse(read("i18n/en.json")), ru = JSON.parse(read("i18n/ru.json"))

// Catalogs stay in step, and plural entries have the forms their language needs.
assert.deepStrictEqual(Object.keys(ru).sort(), Object.keys(en).sort(), "en and ru have different keys")
for (const key of Object.keys(en)) {
  assert.strictEqual(typeof ru[key], typeof en[key], key)
  if (typeof en[key] === "object") {
    assert.deepStrictEqual(Object.keys(en[key]).sort(), ["one", "other"], key)
    assert.deepStrictEqual(Object.keys(ru[key]).sort(), ["few", "many", "one", "other"], key)
  }
  const holes = text => (typeof text === "string" ? text : text.other).match(/%\d/g) || []
  assert.deepStrictEqual(holes(ru[key]).sort(), holes(en[key]).sort(), "placeholders differ: " + key)
}

// Every key the code asks for exists.
for (const file of qml) {
  const source = read(file)
  for (const match of source.matchAll(/\b(?:tn?)\("([a-z][a-z-]*\.[a-z-]+)"/g)) assert(match[1] in en, file + ": missing key " + match[1])
}
for (const key of ["empty", "amount-first", "bad-amount", "name-missing", "goal-format", "action-format", "rate-format"]) assert("entry." + key in en, key)
for (const key of ["url-invalid", "url-insecure"]) assert("setup." + key in en, key)
for (const key of ["forced", "no-key", "no-accounts", "unreachable"]) assert("demo.reason." + key in en, key)

// Text from Sure must never be interpreted as rich text.
for (const file of qml) {
  const source = read(file)
  for (const match of source.matchAll(/(^|\n)\s*Text\s*\{/g)) {
    assert(source.slice(match.index, match.index + 200).includes("Text.PlainText"), file + ": Text without PlainText")
  }
  assert(!/Text\.(RichText|StyledText|AutoText)/.test(source), file + ": rich text")
}

// Colors come from the theme, and "Color" must be qualified: QtQuick has its own.
for (const file of qml) {
  const source = read(file)
  assert(!/(^|[^.\w])Color\./m.test(source), file + ": unqualified Color")
  assert(!/color:\s*"#/.test(source), file + ": hard-coded color")
}

// No API key material or personal paths in the repository.
for (const file of [...qml, "Model.js", "manifest.json", "README.md"]) {
  assert(!/\/home\/[a-z]/.test(read(file)), file + ": absolute home path")
}

// The widget and the manifest agree on the plugin id.
const manifest = JSON.parse(read("manifest.json"))
assert(read("BarWidget.qml").includes('moduleName: "' + manifest.id + '"'))
for (const entry of Object.values(manifest.entryPoints)) assert(fs.existsSync(path.join(root, entry)), entry)

console.log("project tests passed")
