// Checks that a real Sure still answers the way the plugin expects.
// Start the stand with tests/vps/up.sh, then:
//   NODE_EXTRA_CA_CERTS=~/.cache/sure-bar-vps/ca.crt node tests/contract.test.js
const fs = require("fs"), os = require("os"), path = require("path"), vm = require("vm"), assert = require("assert"), {execFileSync} = require("child_process")
const state = process.env.SURE_BAR_VPS_STATE || path.join(os.homedir(), ".cache/sure-bar-vps")
const base = (process.env.SURE_URL || "https://127.0.0.1.nip.io:18443") + "/api/v1"
const keys = Object.fromEntries(fs.readFileSync(path.join(state, "keys"), "utf8").trim().split("\n").map(line => line.split(" ").slice(1)))

async function call(method, route, {key = keys.rw, body} = {}) {
  const res = await fetch(base + route, {method, headers: {"X-Api-Key": key, Accept: "application/json", ...(body ? {"Content-Type": "application/json"} : {})}, body: body ? JSON.stringify(body) : undefined})
  const text = await res.text()
  let json = null
  try { json = JSON.parse(text) } catch {}
  return {status: res.status, json, text, headers: res.headers}
}
const has = (object, fields, where) => { for (const f of fields) assert(f in object, `${where} lacks ${f}`) }
const today = new Date().toISOString().slice(0, 10), month = today.slice(0, 8) + "01"

;(async () => {
  const usage = await call("GET", "/usage")
  assert.strictEqual(usage.status, 200); assert.deepStrictEqual(usage.json.api_key.scopes, ["read_write"])
  assert.deepStrictEqual((await call("GET", "/usage", {key: keys.ro})).json.api_key.scopes, ["read"])

  const bad = await call("GET", "/accounts", {key: "not-a-real-key-123456"})
  assert.strictEqual(bad.status, 401); assert(bad.json, "401 from Sure must be JSON, the plugin relies on it to tell it from a proxy")

  const accounts = await call("GET", "/accounts?per_page=100")
  assert.strictEqual(accounts.status, 200); assert(accounts.json.accounts.length > 0)
  const account = accounts.json.accounts[0]
  has(account, ["id", "name", "currency", "status", "account_type"], "account")

  const flow = await call("GET", "/cash_flow")
  has(flow.json, ["month", "as_of", "time_zone", "currency", "income", "spending"], "cash_flow")
  assert(/^\d{4}-\d{2}-01$/.test(flow.json.month)); assert(/\//.test(flow.json.time_zone), "time_zone must be an IANA name: " + flow.json.time_zone)
  const earlier = await call("GET", "/cash_flow?month=" + month)
  assert.strictEqual(earlier.status, 200)

  const sheet = await call("GET", "/balance_sheet")
  assert("amount" in sheet.json.net_worth)
  const budgets = await call("GET", "/budgets?per_page=6"); assert(Array.isArray(budgets.json.budgets))
  assert.strictEqual((await call("GET", "/budget_categories?per_page=100")).status, 200)

  const tagName = "contract-" + Date.now()
  const tag = await call("POST", "/tags", {body: {tag: {name: tagName}}})
  assert(tag.json && tag.json.id, "creating a tag returns its id")
  const tags = await call("GET", "/tags"); assert(Array.isArray(tags.json)); has(tags.json[0], ["id", "name"], "tag")

  const entry = {account_id: account.id, name: "contract entry", date: today, amount: 12.5, nature: "income", currency: account.currency, tag_ids: [tag.json.id], external_id: "contract-" + Date.now(), source: "sure-bar"}
  const first = await call("POST", "/transactions", {body: {transaction: entry}})
  assert.strictEqual(first.status, 201, first.text.slice(0, 200))
  has(first.json, ["id", "date", "name", "amount_cents", "signed_amount_cents", "currency", "classification", "account", "category", "transfer"], "transaction")
  assert.strictEqual(first.json.amount_cents, 1250); assert.strictEqual(first.json.classification, "income")
  const repeat = await call("POST", "/transactions", {body: {transaction: entry}})
  assert.strictEqual(repeat.status, 200, "the same external_id must not create a second entry"); assert.strictEqual(repeat.json.id, first.json.id)

  const tagged = await call("GET", `/transactions?tag_ids%5B%5D=${tag.json.id}&per_page=100&page=1`)
  assert.strictEqual(tagged.json.transactions.length, 1); assert("total_pages" in tagged.json.pagination)
  assert.strictEqual((await call("GET", `/transactions?tag_ids%5B%5D=${tag.json.id}&start_date=2999-01-01&per_page=100&page=1`)).json.transactions.length, 0)
  assert.strictEqual((await call("GET", "/transactions?search=" + encodeURIComponent("contract entry") + "&per_page=25")).status, 200)

  const readOnly = await call("POST", "/transactions", {key: keys.ro, body: {transaction: entry}})
  assert.strictEqual(readOnly.status, 403)
  assert.strictEqual((await call("DELETE", "/transactions/" + first.json.id)).status, 200)
  // The currency table is a copy of Sure's; the plugin's arithmetic depends on it.
  const compose = path.join(__dirname, "vps/compose.yml")
  const script = 'require "yaml"; require "json"; t = YAML.load_file("/rails/config/currencies.yml"); puts t.values.map { |c| [c["iso_code"], [c["default_precision"] || 2, c["minor_unit_conversion"] || 100]] }.to_h.to_json'
  const real = JSON.parse(execFileSync("docker", ["compose", "-f", compose, "exec", "-T", "web", "ruby", "-e", script], {encoding: "utf8", stdio: ["ignore", "pipe", "ignore"]}))
  const table = vm.runInNewContext(fs.readFileSync(path.join(__dirname, "../Currencies.js"), "utf8").replace(".pragma library", "") + ";TABLE")
  for (const [code, [places, minor]] of Object.entries(real)) {
    assert(table[code], "Currencies.js lacks " + code)
    assert.deepStrictEqual([table[code][2], table[code][3]], [places, minor], "Currencies.js differs for " + code)
  }
  console.log("contract tests passed")
})().catch(error => { console.error(error); process.exit(1) })
