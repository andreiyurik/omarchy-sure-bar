// Runs the real Service.qml in headless Quickshell against a fake Sure.
// Run with: node tests/service.test.js [name-filter]. Needs quickshell, curl and openssl.
const fs = require("fs"), path = require("path"), assert = require("assert"), {execFileSync} = require("child_process")
const {create, row, monthDate} = require("./fake-sure")
const {work, run: runShell, newHome, file, cleanup} = require("./harness/run")

const KEY = "test-key-12345678"
const fast = {businessTag: "business", refreshMinutes: 120, retryBaseMs: 150, retryMaxMs: 400, requestTimeoutMs: 700, probeSeconds: 2}
const run = (home, settings, steps, env) => runShell(home, {...fast, ...settings}, steps, env)
const newHomeWithKey = (key = KEY) => newHome(key)

const tests = []
const test = (name, fn) => tests.push({name, fn})
const noKeyLeft = home => !fs.existsSync(file(home, "api-key"))
const count = (requests, text) => requests.filter(r => r.url.includes(text)).length

test("full refresh, then a cheaper one from the cache", async () => {
  const s = await create(), home = newHomeWithKey()
  const {states} = await run(home, {baseUrl: s.url}, ["idle", {state: "a"}, {call: "refresh"}, {wait: 30}, "idle", {state: "b"}, {call: "refresh", args: [true]}, {wait: 30}, "idle", {state: "c"}])
  assert(states.a.status === "ok" && states.a.current === 1000 && states.a.total === 2200 && states.a.errorKey === "")
  const closed = count(s.requests, "cash_flow?month=")
  assert.strictEqual(closed, 10, "two full refreshes, five closed months each")
  assert.strictEqual(count(s.requests, "start_date="), 1)
  assert.strictEqual(states.b.total, 2200, "cached old revenue still counts")
  assert.strictEqual(s.requests.length, 13 + 7 + 12, "request budget: first 13, cached 7, forced 12")
  s.close()
})
test("sure's own 401 asks for a new key", async () => {
  const s = await create({state: {fault: {match: "/accounts", status: 401, body: {error: "unauthorized"}}}})
  const {states} = await run(newHomeWithKey(), {baseUrl: s.url}, ["idle", {state: "a"}])
  assert(states.a.setupReason === "rejected" && states.a.errorKey === "error.rejected")
  s.close()
})
for (const [name, fault, key] of [
  ["a proxy's 403 page is not a bad key", {status: 403, body: "<html>no</html>", type: "text/html"}, "error.proxy"],
  ["a login page answering 200", {status: 200, body: "<html>login</html>", type: "text/html"}, "error.not-sure"],
  ["html 404 is not sure", {status: 404, body: "<html>nope</html>", type: "text/html"}, "error.not-sure"],
  ["json 404 means an old sure", {status: 404, body: {error: "not_found"}}, "error.not-found"],
  ["broken json", {status: 200, body: "{\"accounts\":[", type: "application/json"}, "error.not-sure"],
  ["json 403 is a refused key", {status: 403, body: {error: "forbidden"}}, "error.forbidden"],
  ["a huge response is refused", {status: 200, body: JSON.stringify({junk: "x".repeat(8100000)})}, "error.too-large"],
]) test(name, async () => {
  const s = await create({state: {fault: {match: "/cash_flow", ...fault}}})
  const {states} = await run(newHomeWithKey(), {baseUrl: s.url}, ["idle", {state: "a"}])
  assert.strictEqual(states.a.errorKey, key); assert.strictEqual(states.a.setupReason, "")
  s.close()
})
test("a server error is retried until it clears", async () => {
  const s = await create({state: {fault: {match: "/cash_flow", status: 500, body: {error: "x"}, times: 12}}})
  const {states} = await run(newHomeWithKey(), {baseUrl: s.url}, ["idle", {state: "a"}, {until: "s.errorKey === '' && s.payload.status === 'ok' && !s.busy"}, {state: "b"}])
  assert.strictEqual(states.a.errorKey, "error.server")
  assert(states.b.current === 1000 && states.b.retryAttempt === 0)
  s.close()
})
test("no retries when background refresh is off", async () => {
  const s = await create({state: {fault: {match: "/cash_flow", status: 500, body: {}}}})
  await run(newHomeWithKey(), {baseUrl: s.url, autoRefresh: false}, ["idle", {wait: 700}])
  assert.strictEqual(count(s.requests, "/accounts"), 1)
  s.close()
})
test("429 waits for Retry-After and sends nothing meanwhile", async () => {
  const s = await create({state: {fault: {match: "/cash_flow", status: 429, body: {error: "rate_limit_exceeded"}, headers: {"Retry-After": "1"}, times: 1}}})
  const {states} = await run(newHomeWithKey(), {baseUrl: s.url}, ["idle", {state: "a"}, {call: "refresh"}, {wait: 200}, {state: "b"}, {until: "s.errorKey === '' && !s.busy"}, {state: "c"}])
  assert(states.a.errorKey === "error.rate-limited" && states.a.blocked && states.a.errorArg === "1")
  assert(states.b.blocked, "still waiting")
  assert.strictEqual(count(s.requests, "/accounts"), 2, "manual refresh while blocked sent nothing")
  assert.strictEqual(states.c.status, "ok")
  s.close()
})
test("a hanging server times out", async () => {
  const s = await create({state: {fault: {match: "/cash_flow", hang: true}}})
  const {states} = await run(newHomeWithKey(), {baseUrl: s.url, autoRefresh: false}, ["idle", {state: "a"}])
  assert.strictEqual(states.a.errorKey, "error.timeout")
  s.close()
})
test("connection errors are told apart", async () => {
  for (const [baseUrl, key] of [["http://127.0.0.1:1", "error.refused"], ["https://no-such-host.invalid", "error.dns"]]) {
    const {states} = await run(newHomeWithKey(), {baseUrl, autoRefresh: false, probeSeconds: 8}, ["idle", {state: "a"}])
    assert.strictEqual(states.a.errorKey, key, baseUrl); assert.strictEqual(states.a.status, "demo")
  }
})
test("an untrusted certificate is named", async () => {
  const dir = fs.mkdtempSync(path.join(work, "tls-"))
  execFileSync("openssl", ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", dir + "/k", "-out", dir + "/c", "-days", "2", "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost,IP:127.0.0.1"], {stdio: "ignore"})
  const s = await create({tls: {key: fs.readFileSync(dir + "/k"), cert: fs.readFileSync(dir + "/c")}})
  const {states} = await run(newHomeWithKey(), {baseUrl: s.url, autoRefresh: false}, ["idle", {state: "a"}])
  assert.strictEqual(states.a.errorKey, "error.tls")
  s.close()
})
test("losing the network keeps real numbers and recovers by itself", async () => {
  const s = await create()
  const {states} = await run(newHomeWithKey(), {baseUrl: s.url}, ["idle", {state: "a"}, {http: {url: s.url + "/__control", body: {down: true}}}, {call: "refresh"}, {wait: 30}, "idle", {state: "b"},
    {http: {url: s.url + "/__control", body: {down: false}}}, {until: "s.errorKey === '' && !s.busy"}, {state: "c"}])
  assert(states.b.status === "ok" && !states.b.demo && states.b.current === 1000 && states.b.errorKey !== "" && states.b.retrying)
  assert.strictEqual(states.c.errorKey, "")
  s.close()
})
test("starting offline shows the last numbers, not demo ones", async () => {
  const s = await create(), home = newHomeWithKey()
  const first = await run(home, {baseUrl: s.url}, ["idle", {wait: 150}])
  assert.strictEqual(fs.statSync(file(home, "snapshot.json")).mode & 0o777, 0o600)
  s.state.down = true
  const {states} = await run(home, {baseUrl: s.url, autoRefresh: false}, ["idle", {state: "a"}])
  assert(states.a.status === "ok" && !states.a.demo && states.a.current === 1000 && states.a.total === 2200 && states.a.errorKey !== "" && states.a.updatedAt > 0 && first)
  s.close()
})
test("a snapshot from another server is never shown", async () => {
  const s = await create(), home = newHomeWithKey()
  await run(home, {baseUrl: s.url}, ["idle", {wait: 150}])
  const {states} = await run(home, {baseUrl: "http://127.0.0.1:1", autoRefresh: false}, ["idle", {state: "a"}])
  assert(states.a.demo && states.a.current !== 1000)
  s.close()
})
test("a damaged snapshot and plan are ignored", async () => {
  const s = await create(), home = newHomeWithKey()
  fs.writeFileSync(file(home, "snapshot.json"), "{not json"); fs.writeFileSync(file(home, "plan.json"), "[[[")
  const {states} = await run(home, {baseUrl: s.url}, ["idle", {state: "a"}])
  assert(states.a.status === "ok" && states.a.goal === null)
  s.close()
})
test("reads every page", async () => {
  const many = Array.from({length: 250}, (_, i) => row("m" + i, monthDate(0, 1), "m", 1, "income", ["tag-biz"]))
  const s = await create({state: {transactions: many}})
  const {states} = await run(newHomeWithKey(), {baseUrl: s.url}, ["idle", {state: "a"}])
  assert(states.a.total === 250 && count(s.requests, "tag_ids") === 3 && states.a.warnings.length === 0)
  s.close()
})
test("says so when history is cut off", async () => {
  const many = Array.from({length: 3050}, (_, i) => row("m" + i, monthDate(0, 1), "m", 1, "income", ["tag-biz"]))
  const s = await create({state: {transactions: many}})
  const {states} = await run(newHomeWithKey(), {baseUrl: s.url, requestTimeoutMs: 4000}, ["idle", {state: "a"}])
  assert(states.a.warnings.includes("warn.truncated") && states.a.total === 3000)
  s.close()
})
test("a lost reply can't create a duplicate entry", async () => {
  const s = await create({state: {fault: {match: "/transactions", method: "POST", dropAfter: true, times: 1}}})
  const {callbacks} = await run(newHomeWithKey(), {baseUrl: s.url}, ["idle", {call: "addEntry", args: ["+50 lunch"], callback: "first"}, "idle", {call: "addEntry", args: ["+50 lunch"], callback: "second"}, "idle", {call: "addEntry", args: ["+50 dinner"], callback: "third"}, "idle"])
  assert(!callbacks.first.ok && callbacks.second.ok && callbacks.third.ok)
  assert.strictEqual(s.state.transactions.filter(t => t.name === "lunch").length, 1)
  assert.strictEqual(s.state.transactions.filter(t => t.source === "sure-bar").length, 2)
  s.close()
})
test("view-only key blocks entries but not goals", async () => {
  const s = await create({state: {scopes: ["read"]}})
  const {states, callbacks} = await run(newHomeWithKey(), {baseUrl: s.url}, ["idle", {until: "s.readOnly"}, {call: "addEntry", args: ["5 x"], callback: "e"}, {call: "runCommand", args: [{ok: true, kind: "goal", off: false, amount: 7000}]}, {state: "a"}])
  assert(!callbacks.e.ok && callbacks.e.text === "entry.read-only" && states.a.goal === 7000 && states.a.readOnly)
  assert.strictEqual(s.requests.filter(r => r.method === "POST").length, 0)
  s.close()
})
test("connect checks the server and key before saving anything", async () => {
  const s = await create({state: {validKey: "the-right-key-123"}}), home = newHomeWithKey(null)
  const {states} = await run(home, {baseUrl: "http://127.0.0.1:1"}, ["idle", {state: "start"}, {call: "connect", args: [s.url, "the-wrong-key-123"]}, {wait: 20}, "idle", {state: "wrong"},
    {call: "connect", args: [s.url, "the-right-key-123"]}, {wait: 20}, {until: "s.hasKey && !s.busy && s.payload.status === 'ok'"}, {state: "right"}])
  assert(states.start.setupReason === "no-key" && states.wrong.setupError === "setup.rejected")
  assert.strictEqual(fs.readFileSync(file(home, "api-key"), "utf8").trim(), "the-right-key-123")
  assert.strictEqual(fs.statSync(file(home, "api-key")).mode & 0o777, 0o600)
  assert(states.right.baseUrl === s.url && states.right.current === 1000 && states.right.setupReason === "" && states.right.setupError === "")
  s.close()
})
test("connect explains bad addresses and old servers without saving", async () => {
  const old = await create({state: {fault: {match: "/cash_flow", status: 404, body: {error: "not_found"}}}}), home = newHomeWithKey(null)
  const {states} = await run(home, {baseUrl: "http://127.0.0.1:1"}, ["idle",
    {call: "connect", args: ["not a url", "some-valid-key-1"]}, {wait: 20}, "idle", {state: "bad"},
    {call: "connect", args: ["http://sure.example.com", "some-valid-key-1"]}, {wait: 20}, "idle", {state: "insecure"},
    {call: "connect", args: ["http://127.0.0.1:1", "some-valid-key-1"]}, {wait: 20}, "idle", {state: "refused"},
    {call: "connect", args: [old.url, "some-valid-key-1"]}, {wait: 20}, "idle", {state: "old"}])
  assert.strictEqual(states.bad.setupError, "setup.url-invalid"); assert.strictEqual(states.insecure.setupError, "setup.url-insecure")
  assert.strictEqual(states.refused.setupError, "error.refused"); assert.strictEqual(states.old.setupError, "error.not-found")
  assert(noKeyLeft(home))
  old.close()
})
test("timezone mismatch is said once", async () => {
  const s = await create({state: {zone: "Asia/Tokyo"}}), home = newHomeWithKey()
  const {states} = await run(home, {baseUrl: s.url}, ["idle", {until: "s.timezoneNote !== null"}, {state: "a"}, {call: "dismissNote", args: ["tz:Asia/Tokyo|+0000"]}, {state: "b"}, {wait: 120}], {TZ: "UTC"})
  assert.strictEqual(states.a.zone, "tz:Asia/Tokyo|+0000"); assert.strictEqual(states.b.zone, "")
  const again = await run(home, {baseUrl: s.url}, ["idle", {until: "s.timezoneNote !== null"}, {wait: 100}, {state: "a"}], {TZ: "UTC"})
  assert.strictEqual(again.states.a.zone, "")
  s.close()
})
test("matching timezones say nothing", async () => {
  const s = await create({state: {zone: "UTC"}})
  const {states} = await run(newHomeWithKey(), {baseUrl: s.url}, ["idle", {wait: 200}, {state: "a"}], {TZ: "UTC"})
  assert.strictEqual(states.a.zone, "")
  s.close()
})
test("today's entry counts when the server's clock is a day behind", async () => {
  const s = await create({state: {asOfOffset: -1, transactions: []}})
  const {states, callbacks} = await run(newHomeWithKey(), {baseUrl: s.url}, ["idle", {call: "addEntry", args: ["+300 client #b"], callback: "e"}, {wait: 30}, "idle", {state: "a"}])
  assert(callbacks.e.ok && states.a.current === 300)
  s.close()
})
test("money in another currency waits for a rate, then counts everywhere", async () => {
  const transactions = [row("u1", monthDate(0, 1), "Client", 100, "income", ["tag-biz"], "USD"), row("r1", monthDate(0, 1), "Local", 500, "income", ["tag-biz"], "RUB")]
  const s = await create({state: {currency: "RUB", transactions}}), home = newHomeWithKey()
  const rate = {ok: true, kind: "rate", off: false, currency: "USD", value: 92}, goal = {ok: true, kind: "goal", off: false, amount: 1000, currency: "USD"}
  const {states} = await run(home, {baseUrl: s.url}, ["idle", {state: "before"}, {call: "runCommand", args: [goal]}, {state: "goal"}, {call: "runCommand", args: [rate]}, {state: "after"}, {wait: 150}])
  assert(states.before.current === 500 && states.before.unconverted[0].currency === "USD" && states.before.unconverted[0].amount === 100)
  assert(states.goal.goal === null && states.goal.goalCurrency === "USD")
  assert(states.after.current === 9700 && states.after.unconverted.length === 0 && states.after.goal === 92000 && states.after.bizIncome === 9700 && states.after.rates[0].value === 92)
  const again = await run(home, {baseUrl: s.url}, ["idle", {state: "a"}])
  assert.strictEqual(again.states.a.current, 9700, "the rate is saved")
  s.close()
})
test("a demo uses the main currency of a Sure with no accounts yet", async () => {
  const s = await create({state: {currency: "EUR", accounts: []}})
  const {states} = await run(newHomeWithKey(), {baseUrl: s.url}, ["idle", {state: "a"}])
  assert(states.a.demo && states.a.currency === "EUR")
  s.close()
})
test("amounts follow the language's format", async () => {
  const s = await create()
  const {states} = await run(newHomeWithKey(), {baseUrl: s.url}, ["idle", {state: "a"}])
  assert(states.a.sample === "$9.50" && states.a.sampleWhole === "$7,000", JSON.stringify([states.a.sample, states.a.sampleWhole]))
  s.close()
})
test("waking from sleep refreshes", async () => {
  const s = await create()
  await run(newHomeWithKey(), {baseUrl: s.url, tickMs: 60}, ["idle", {call: "refresh", args: [false]}, {wait: 20}, "idle", {until: "(s.now = new Date(Date.now() - 600000), true)"}, {wait: 220}, "idle"])
  assert(count(s.requests, "/accounts") >= 3)
  s.close()
})

;(async () => {
  const filter = process.argv[2] || ""
  let failed = 0, passed = 0
  for (const {name, fn} of tests) {
    if (!name.includes(filter)) continue
    try { await fn(); passed++; console.log("  ok  " + name) }
    catch (error) { failed++; console.log("FAIL  " + name + "\n" + String(error.stack || error).slice(0, 1800)) }
  }
  cleanup()
  console.log(failed ? `${failed} failed, ${passed} passed` : `service tests passed (${passed})`)
  process.exit(failed ? 1 : 0)
})()
