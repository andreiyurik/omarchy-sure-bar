// The plugin against a real Sure behind HTTPS, on a network that gets slow and goes away.
// Run tests/vps/up.sh first. Linux only: trusts the stand's CA in a private mount namespace,
// so the system's certificates are not touched.
const fs = require("fs"), os = require("os"), path = require("path"), assert = require("assert")
const {run, newHome, file, cleanup} = require("../harness/run")

const state = process.env.SURE_BAR_VPS_STATE || path.join(os.homedir(), ".cache/sure-bar-vps"), url = "https://127.0.0.1.nip.io:18443", api = "http://127.0.0.1:18474"
const keys = Object.fromEntries(fs.readFileSync(path.join(state, "keys"), "utf8").trim().split("\n").map(line => line.split(" ").slice(1)))
const wrap = command => ["unshare", "-r", "-m", "sh", "-c", 'mount --bind "$CERTS" /etc/ssl/certs && exec "$@"', "sh", ...command]
const settings = {baseUrl: "http://127.0.0.1:1", businessTag: "business", refreshMinutes: 120, retryBaseMs: 400, retryMaxMs: 1500, requestTimeoutMs: 6000, probeSeconds: 4}
const go = (home, steps, more) => run(home, {...settings, ...more}, steps, {CERTS: path.join(state, "certs")}, {wrap, limitMs: 90000})
const toxic = (body, target = "/proxies/vps/toxics") => ({http: {url: api + target, body}})
const reset = {http: {url: api + "/reset"}}
const settled = {until: "!s.busy && !s.saving"}
// Every connection is reset, as when the network goes away mid-request.
const cut = toxic({type: "reset_peer", attributes: {timeout: 0}})

;(async () => {
  const home = newHome(null)
  const {states: s, callbacks: c} = await go(home, [reset, "idle", {state: "start"},
    {call: "connect", args: [url, keys.rw]}, {wait: 30}, {until: "s.hasKey && !s.busy && s.payload.status === 'ok'"}, {state: "connected"},
    {call: "addEntry", args: ["+5000 client #b"], callback: "income"}, {wait: 30}, settled, {state: "income"},
    {call: "runCommand", args: [{ok: true, kind: "goal", off: false, amount: 7000}]}, {state: "goal"},

    toxic({type: "latency", attributes: {latency: 250, jitter: 50}}),
    {state: "full-start"}, {call: "refresh", args: [true]}, {wait: 30}, settled, {state: "full-end"},
    {call: "refresh"}, {wait: 30}, settled, {state: "cached-end"},
    {call: "addEntry", args: ["45 coffee"], callback: "slow-entry"}, {wait: 30}, settled, {state: "slow"},
    reset,

    cut, {call: "refresh"}, {wait: 30}, settled, {until: "!s.probing"}, {state: "cut"},
    reset, {until: "s.errorKey === '' && !s.busy"}, {state: "back"},
    toxic({type: "timeout", attributes: {timeout: 0}}), {call: "refresh"}, {wait: 30}, settled, {state: "blackhole"}, reset,
    {until: "s.errorKey === '' && !s.busy"}, {state: "recovered"},
    {call: "undoLast"}, {wait: 30}, settled, {wait: 300}, settled, {state: "undone"}], {requestTimeoutMs: 6000})

  assert(s.start.setupReason === "no-key" && s.connected.baseUrl === url && !s.connected.readOnly && s.connected.errorKey === "")
  assert.strictEqual(fs.statSync(file(home, "api-key")).mode & 0o777, 0o600)
  assert(c.income.ok, c.income.text); assert.strictEqual(s.income.current - s.connected.current, 5000)
  assert.strictEqual(s.goal.goal, 7000)
  assert(c["slow-entry"].ok, c["slow-entry"].text)
  assert.strictEqual(s.cut.status, "ok"); assert.strictEqual(s.cut.errorKey, "error.unreachable"); assert.strictEqual(s.cut.current, s.income.current)
  assert.strictEqual(s.back.errorKey, ""); assert.strictEqual(s.blackhole.errorKey, "error.timeout"); assert.strictEqual(s.recovered.errorKey, "")
  assert.strictEqual(s.undone.errorKey, "")
  console.log(`over a 250 ms link: full refresh ${s["full-end"].at - s["full-start"].at} ms, cached refresh ${s["cached-end"].at - s["full-end"].at} ms`)

  const offline = newHome(keys.rw)
  fs.copyFileSync(file(home, "snapshot.json"), file(offline, "snapshot.json"))
  const later = await go(offline, [cut, "idle", {until: "!s.probing"}, {state: "offline"}, reset], {baseUrl: url, autoRefresh: false})
  assert(later.states.offline.status === "ok" && !later.states.offline.demo && later.states.offline.errorKey === "error.unreachable")

  const viewer = newHome(keys.ro)
  const ro = await go(viewer, ["idle", {until: "s.readOnly"}, {call: "addEntry", args: ["5 nope"], callback: "e"}, {state: "a"}], {baseUrl: url})
  assert(ro.states.a.readOnly && !ro.callbacks.e.ok)
  cleanup()
  console.log("vps tests passed")
})().catch(error => { console.error(error); cleanup(); process.exit(1) })
