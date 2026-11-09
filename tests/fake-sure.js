// A small stand-in for Sure's API that can misbehave on request.
const http = require("http"), https = require("https")

const pad = n => String(n).padStart(2, "0")
const iso = d => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
const today = new Date()
const monthDate = (back, day) => iso(new Date(today.getFullYear(), today.getMonth() - back, day))

function defaultTransactions() {
  return [[0, 1, 1000], [1, 3, 500], [3, 5, 700]].map(([back, day, amount], i) => row(`seed-${i}`, monthDate(back, day), `Client ${i}`, amount, "income", ["tag-biz"]))
}
function row(id, date, name, amount, classification, tags) {
  const cents = Math.round(amount * 100)
  return {id, date, name, amount_cents: cents, signed_amount_cents: classification === "income" ? cents : -cents, currency: "USD", classification, tag_ids: tags || [],
    account: {id: "acc-1", name: "Cash"}, category: null, transfer: null, external_id: null, source: null}
}

function create(options = {}) {
  const state = {fault: null, down: false, scopes: ["read_write"], zone: "UTC", validKey: null, transactions: defaultTransactions(), accounts: [{id: "acc-1", name: "Cash", currency: "USD", status: "active", account_type: "depository"}], ...options.state}
  const requests = []
  const send = (res, status, body, headers = {}, type = "application/json") => {
    res.writeHead(status, {"Content-Type": type, ...headers})
    res.end(typeof body === "string" ? body : JSON.stringify(body))
  }
  const handler = (req, res) => {
    let raw = ""
    req.on("data", chunk => { raw += chunk })
    req.on("end", () => {
      const url = new URL(req.url, "http://x")
      if (url.pathname === "/__control") { Object.assign(state, JSON.parse(raw || "{}")); return send(res, 200, {}) }
      requests.push({method: req.method, url: req.url, key: req.headers["x-api-key"], body: raw ? JSON.parse(raw) : null})
      if (state.down) return req.socket.destroy()
      const fault = state.fault
      let after = null
      if (fault && req.url.includes(fault.match) && (!fault.method || fault.method === req.method)) {
        if (fault.times !== undefined && --fault.times < 0) state.fault = null
        else {
          if (fault.hang) return
          if (fault.drop) return req.socket.destroy()
          if (fault.dropAfter) after = () => req.socket.destroy()
          else return send(res, fault.status, fault.body === undefined ? {} : fault.body, fault.headers, fault.type)
        }
      }
      if (state.validKey && req.headers["x-api-key"] !== state.validKey) return send(res, 401, {error: "unauthorized", message: "invalid"})
      if (after) { route(req, url, raw, () => {}); return after() }
      route(req, url, raw, (status, body) => send(res, status, body))
    })
  }
  function route(req, url, raw, reply) {
    const path = url.pathname.replace("/api/v1", ""), q = url.searchParams
    if (path === "/usage") return reply(200, {api_key: {name: "k", scopes: state.scopes}, rate_limit: {tier: "noop"}})
    if (path === "/accounts") return reply(200, {accounts: state.accounts})
    if (path === "/cash_flow") {
      const month = q.get("month") || monthDate(0, 1)
      const income = state.transactions.filter(t => t.date.startsWith(month.slice(0, 7)) && t.classification === "income").reduce((sum, t) => sum + t.amount_cents / 100, 0)
      return reply(200, {month, as_of: iso(new Date(today.getFullYear(), today.getMonth(), today.getDate() + (state.asOfOffset || 0))), time_zone: state.zone, currency: "USD", income: String(income), spending: "10.0"})
    }
    if (path === "/balance_sheet") return reply(200, {net_worth: {amount: "5000.0"}})
    if (path === "/tags") return reply(200, [{id: "tag-biz", name: "business"}])
    if (path === "/budgets") return reply(200, {budgets: []})
    if (path === "/transactions" && req.method === "GET") {
      let list = state.transactions.slice().sort((a, b) => (a.date < b.date ? 1 : -1))
      if (q.get("tag_ids[]")) list = list.filter(t => t.tag_ids.includes(q.get("tag_ids[]")))
      if (q.get("start_date")) list = list.filter(t => t.date >= q.get("start_date"))
      if (q.get("search")) list = list.filter(t => t.name.includes(q.get("search")))
      const per = Math.min(100, Number(q.get("per_page")) || 25), page = Number(q.get("page")) || 1
      return reply(200, {transactions: list.slice((page - 1) * per, page * per), pagination: {page, per_page: per, total_count: list.length, total_pages: Math.max(1, Math.ceil(list.length / per))}})
    }
    if (path === "/transactions" && req.method === "POST") {
      const t = JSON.parse(raw).transaction
      const existing = t.external_id && state.transactions.find(item => item.external_id === t.external_id && item.source === t.source)
      if (existing) return reply(200, existing)
      const made = row(`new-${state.transactions.length}`, t.date, t.name, t.amount, t.nature, t.tag_ids)
      made.external_id = t.external_id; made.source = t.source
      state.transactions.push(made)
      return reply(201, made)
    }
    if (path.startsWith("/transactions/") && req.method === "DELETE") {
      state.transactions = state.transactions.filter(t => t.id !== path.split("/").pop())
      return reply(200, {})
    }
    reply(404, {error: "not_found"})
  }
  const server = options.tls ? https.createServer(options.tls, handler) : http.createServer(handler)
  return new Promise(resolve => server.listen(0, "127.0.0.1", () => {
    const port = server.address().port
    resolve({state, requests, port, url: `${options.tls ? "https" : "http"}://127.0.0.1:${port}`, close: () => { server.closeAllConnections(); server.close() }})
  }))
}

module.exports = {create, row, monthDate, iso}
