import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons
import "Model.js" as Model

Item {
  id: root
  // Third-party services can't read shell.json, so the bar widget hands over its settings.
  property var widgetSettings: null
  property var payload: null
  property bool busy: false
  property bool saving: false
  property var lastAdded: null
  property var plan: Model.emptyPlan()
  property var gameSource: null
  property string apiKey: ""
  property bool keyChecked: false
  property bool amountsHidden: false
  property date updatedAt: new Date(0)
  property date now: new Date()

  // Why the panel shows the connect screen: "", no-key, rejected, url-invalid, url-insecure.
  property string setupReason: ""
  property string setupError: ""
  property bool connecting: false
  property string errorKey: ""
  property string errorArg: ""

  // Test seams: settings without a running shell, and no desktop notifications.
  property var overrides: null
  property bool silent: false
  property string lastNotice: ""

  property var accounts: []
  property var tags: []
  property var inflight: []
  property int generation: 0
  property string pendingNotice: ""

  readonly property int maxResponseChars: 8000000
  readonly property int maxPages: 30
  readonly property string configDir: (Quickshell.env("HOME") || "") + "/.config/sure-bar"

  Commons.Translations { id: catalog; directory: Qt.resolvedUrl("i18n") }
  function t(key) { return catalog.t(key) }
  function tn(key, count) { return catalog.tn(key, count) }

  readonly property var settings: overrides || widgetSettings || ({})
  readonly property bool configured: !!overrides || widgetSettings !== null
  readonly property var server: Model.origin(settings.baseUrl || "http://localhost:3000", settings.allowInsecureHttp === true)
  readonly property string baseUrl: server.ok ? server.url : ""
  readonly property string businessTag: String(settings.businessTag || "business")
  readonly property bool trackAllIncome: settings.trackAllIncome === true
  readonly property string defaultAccount: String(settings.defaultAccount || "")
  readonly property bool autoRefresh: settings.autoRefresh !== false
  readonly property int refreshMinutes: Math.max(1, Math.min(120, Number(settings.refreshMinutes) || 10))
  readonly property bool forcedDemo: settings.demoMode === true

  readonly property bool isDemo: !payload || payload.status === "demo"
  readonly property bool needsSetup: setupReason !== ""
  readonly property string currency: payload ? payload.currency : "USD"
  readonly property var game: payload ? payload.game : null
  readonly property var runway: payload ? Model.runway(payload.netWorth, Model.view(payload, "all").burn) : null
  readonly property bool alarm: !isDemo && ((!!payload.budget && !!payload.budget.pace && payload.budget.pace.status === "over") || (runway !== null && runway < 3))
  readonly property string message: errorKey ? t(errorKey).replace("%1", errorArg) : ""

  // Display helpers. Every amount on screen goes through money(), so hiding amounts has one switch.
  readonly property var locale: Qt.locale(Commons.I18n.formatLocale)
  function plainMoney(value, code) { return Model.formatMoney(value, code || currency, locale.groupSeparator) }
  function money(value, code) { return amountsHidden ? "•••" : plainMoney(value, code) }
  function signed(value, code) { return amountsHidden ? "•••" : (value > 0 ? "+" : "") + plainMoney(value, code) }
  function shortMoney(value) {
    return amountsHidden ? "•••" : Model.shortMoney(value, {k: t("short.k"), m: t("short.m"), decimal: locale.decimalPoint})
  }
  function monthName(index) { return locale.standaloneMonthName(index) }
  function monthShort(index) { return locale.standaloneMonthName(index, Locale.ShortFormat).replace(/\.$/, "") }
  function monthOf(isoDate) { return monthShort(Model.monthIndex(isoDate)) }
  function number(value, decimals) { return Commons.I18n.formatNumber(value, decimals) }
  function runwayText() { return runway === null ? t("growth.runway-unknown") : t("growth.runway-value").arg(number(Math.round(runway * 10) / 10, 1)) }

  function raceText(g) {
    if (!g) return ""
    if (g.goal) {
      if (g.goal.over > 0) return t("race.goal-over").arg(money(g.goal.over))
      if (g.goal.reached) return t("race.goal-reached")
      return t("race.goal").arg(number(g.goal.percent, 0)).arg(money(g.goal.stage.remaining)).arg(money(g.goal.stage.target))
    }
    if (g.delta !== null) return (g.delta >= 0 ? t("race.ahead") : t("race.behind")).arg(number(Math.abs(g.delta), 0))
    if (!g.next) return t("race.all-done")
    if (g.next.target === 1) return t("race.first-payment")
    return t("race.to-next").arg(money(g.next.remaining))
  }
  function winTitle(win) {
    if (win.kind === "first-profit") return t("win.first-profit")
    if (win.kind === "three-months") return t("win.three-months")
    return win.target === 1 ? t("win.first-payment") : t("win.revenue").arg(money(win.target))
  }
  function barText(compact) {
    var g = game
    if (!g || needsSetup) return "◎"
    if (g.goal) {
      var progress = g.goal.reached ? "★" : number(g.goal.percent, 0) + "%"
      return compact || amountsHidden || g.current <= 0 ? progress : shortMoney(g.current) + " " + progress
    }
    var arrow = g.delta === null ? "" : g.delta >= 0 ? "▲" : "▼"
    if (compact || amountsHidden || g.current <= 0) return arrow || "◎"
    return shortMoney(g.current) + (arrow ? " " + arrow : "")
  }
  function updatedText() {
    var minutes = Math.floor((now.getTime() - updatedAt.getTime()) / 60000)
    if (updatedAt.getTime() === 0) return ""
    if (minutes < 1) return t("footer.updated-now")
    if (minutes < 60) return tn("footer.updated-min", minutes).arg(number(minutes, 0))
    var hours = Math.floor(minutes / 60)
    return tn("footer.updated-hours", hours).arg(number(hours, 0))
  }
  function previewAccount(hint) {
    var last = payload && payload.recent && payload.recent[0] ? payload.recent[0].accountId : ""
    return Model.pickAccount(accounts, hint, defaultAccount, last)
  }

  onConfiguredChanged: refresh()
  onForcedDemoChanged: refresh()
  onBaseUrlChanged: refresh()
  Connections {
    target: Commons.I18n
    function onLanguageChanged() { if (root.isDemo) root.refresh() }
  }

  FileView {
    id: keyFile
    path: root.configDir + "/api-key"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { root.apiKey = text().trim(); root.keyChecked = true; root.refresh() }
    onLoadFailed: { root.apiKey = ""; root.keyChecked = true; root.refresh() }
  }
  FileView {
    id: prefsFile
    path: root.configDir + "/hide-amounts"
    printErrors: false
    onLoaded: root.amountsHidden = text().trim() === "1"
  }

  FileView {
    id: planFile
    path: root.configDir + "/plan.json"
    printErrors: false
    onLoaded: {
      var raw = null
      try { raw = JSON.parse(text()) } catch (error) { raw = null }
      root.plan = Model.normalizePlan(raw)
      root.rebuildGame()
    }
  }

  // The key goes over stdin so it never shows up in a process list.
  Process {
    id: keyWriter
    property string pending: ""
    stdinEnabled: true
    command: ["sh", "-c", 'umask 077; mkdir -p "$1" && cat > "$2" && chmod 600 "$2"', "sh", root.configDir, root.configDir + "/api-key"]
    onStarted: { write(pending + "\n"); pending = ""; stdinEnabled = false }
    onExited: function(code) {
      stdinEnabled = true
      root.connecting = false
      if (code === 0) keyFile.reload()
      else root.setupError = "setup.save-failed"
    }
  }
  Process { id: prefsWriter }
  Process { id: planWriter }
  Process {
    id: entryNotice
    stdout: StdioCollector { onStreamFinished: if (text.trim() === "undo") root.undoLast() }
  }

  Timer { interval: root.refreshMinutes * 60000; running: root.autoRefresh; repeat: true; onTriggered: root.refresh() }
  Timer { interval: 30000; running: true; repeat: true; onTriggered: root.now = new Date() }
  // Sure recalculates balances in a background job after each write.
  Timer { id: settle; interval: 4000; onTriggered: root.refresh() }
  Timer {
    id: watchdog
    interval: 15000
    onTriggered: root.inflight.slice().forEach(function(xhr) { xhr.abort() })
  }

  function api(method, path, body, done, keyOverride) {
    var xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      var index = root.inflight.indexOf(xhr)
      if (index < 0) return
      root.inflight.splice(index, 1)
      if (!root.inflight.length) watchdog.stop()
      if (xhr.responseText && xhr.responseText.length > root.maxResponseChars) { done(false, null, -1); return }
      var ok = xhr.status >= 200 && xhr.status < 300, data = null
      if (xhr.responseText) { try { data = JSON.parse(xhr.responseText) } catch (error) { ok = false } }
      done(ok, data, xhr.status)
    }
    xhr.open(method, baseUrl + "/api/v1" + path)
    xhr.setRequestHeader("X-Api-Key", keyOverride || apiKey)
    xhr.setRequestHeader("Accept", "application/json")
    if (body) xhr.setRequestHeader("Content-Type", "application/json")
    inflight.push(xhr)
    watchdog.restart()
    xhr.send(body ? JSON.stringify(body) : "")
  }

  function fetchAll(requests, done) {
    var results = {}, left = requests.length, failure = null
    if (!left) { done(null, results); return }
    requests.forEach(function(request) {
      api("GET", request.path, null, function(ok, data, status) {
        if (!ok && failure === null) failure = status
        results[request.key] = data
        if (--left === 0) done(failure, results)
      })
    })
  }

  function errorFor(status) {
    if (status === 401 || status === 403) return "error.rejected"
    if (status === 0) return "error.unreachable"
    if (status === 404) return "error.not-found"
    if (status === -1) return "error.too-large"
    if (status >= 200 && status < 300) return "error.bad-response"
    return "error.http"
  }
  function setError(status) {
    errorKey = errorFor(status)
    errorArg = String(status)
  }

  function showDemo(reason) {
    busy = false
    errorKey = ""
    var names = {groceries: t("demo.groceries"), ads: t("demo.ads"), cafe: t("demo.cafe"), subscriptions: t("demo.subscriptions"),
      coffee: t("demo.coffee"), server: t("demo.server"), client: t("demo.client")}
    names.action = t("demo.action")
    gameSource = null
    payload = Model.demo(new Date(), reason, Commons.I18n.language.indexOf("ru") === 0 ? "RUB" : "USD", names, plan)
  }

  function refresh() {
    if (!keyChecked || !configured) return
    var token = ++generation
    setupReason = ""
    if (forcedDemo) { showDemo("demo.reason.forced"); return }
    if (!server.ok) { setupReason = server.error; showDemo("demo.reason.no-key"); return }
    if (!apiKey) { setupReason = "no-key"; showDemo("demo.reason.no-key"); return }
    busy = true
    var alive = function() { return token === generation }
    var fail = function(status) {
      if (!alive()) return
      busy = false
      if (status === 401 || status === 403) setupReason = "rejected"
      setError(status)
      flushNotice()
      if (!payload) { var key = errorKey, arg = errorArg; showDemo("demo.reason.unreachable"); errorKey = key; errorArg = arg }
    }
    fetchAll([
      {key: "accounts", path: "/accounts?per_page=100"},
      {key: "cash", path: "/cash_flow"},
      {key: "sheet", path: "/balance_sheet"},
      {key: "tags", path: "/tags"},
      {key: "recent", path: "/transactions?per_page=6"},
      {key: "budgets", path: "/budgets?per_page=6"}
    ], function(failure, base) {
      if (!alive()) return
      if (failure !== null) { fail(failure); return }
      root.accounts = (base.accounts.accounts || []).slice(0, 200)
      root.tags = (base.tags || []).slice(0, 1000)
      if (!root.accounts.length) { showDemo("demo.reason.no-accounts"); return }
      var months = Model.monthsBack(base.cash.month, 6)
      var requests = months.slice(0, -1).map(function(month) { return {key: month, path: "/cash_flow?month=" + month} })
      var current = (base.budgets.budgets || []).filter(function(budget) { return budget.current })[0]
      if (current) {
        requests.push({key: "budget", path: "/budgets/" + encodeURIComponent(current.id)})
        requests.push({key: "budgetCategories", path: "/budget_categories?per_page=100"})
      }
      fetchAll(requests, function(failure2, detail) {
        if (!alive()) return
        if (failure2 !== null) { fail(failure2); return }
        var lines = (current && detail.budgetCategories ? detail.budgetCategories.budget_categories || [] : [])
          .filter(function(line) { return line.budget_id === current.id && line.budgeted_spending_cents > 0 })
          .sort(function(a, b) { return b.budgeted_spending_cents - a.budgeted_spending_cents })
          .slice(0, 8)
        fetchAll(lines.map(function(line) { return {key: line.id, path: "/budget_categories/" + encodeURIComponent(line.id)} }), function(failure3, categories) {
          if (!alive()) return
          if (failure3 !== null) { fail(failure3); return }
          loadRevenue(months, base.cash.currency, 1, [], function(revenue, failure4) {
            if (!alive()) return
            if (failure4 !== null) { fail(failure4); return }
            compose(base, detail, months, lines, categories, revenue)
          }, alive)
        })
      })
    })
  }

  function businessTagObject() {
    var name = businessTag.toLowerCase()
    return root.tags.filter(function(tag) { return String(tag.name).toLowerCase() === name })[0] || null
  }

  function revenueResult(transactions, months, currency, truncated) {
    var result = Model.aggregateTagged(transactions, months, currency)
    result.transactions = transactions
    result.truncated = truncated
    return result
  }

  // Sure lists newest first, so hitting the page cap loses the oldest history; that is reported.
  function loadRevenue(months, currency, page, collected, done, alive) {
    var tag = trackAllIncome ? null : businessTagObject()
    if (!tag && !trackAllIncome) { done(revenueResult([], months, currency, false), null); return }
    var filter = tag ? "tag_ids%5B%5D=" + encodeURIComponent(tag.id) + "&" : ""
    api("GET", "/transactions?" + filter + "per_page=100&page=" + page, null, function(ok, data, status) {
      if (!alive()) return
      if (!ok) { done(null, status); return }
      var all = collected.concat(data.transactions || [])
      var pages = data.pagination ? data.pagination.total_pages : 1
      if (page < pages && page < root.maxPages) loadRevenue(months, currency, page + 1, all, done, alive)
      else done(revenueResult(all, months, currency, page < pages), null)
    })
  }

  function recentRow(item) {
    return {id: item.id, date: item.date, name: String(item.name || "").slice(0, 80), amount: Model.fromMinor(item.signed_amount_cents, item.currency),
      currency: item.currency, category: item.category ? String(item.category.name).slice(0, 40) : "", accountId: item.account ? item.account.id : ""}
  }

  function compose(base, detail, months, lines, categories, revenue) {
    var code = base.cash.currency
    var series = months.map(function(month) {
      var flow = month === base.cash.month ? base.cash : detail[month]
      return {month: month, income: Model.num(flow.income), spending: Model.num(flow.spending)}
    })
    var asOf = new Date(base.cash.as_of + "T00:00:00")
    var previousGame = payload && payload.status === "ok" ? payload.game : null
    gameSource = {transactions: revenue.transactions, asOf: asOf, currency: code}
    var currentGame = Model.game(revenue.transactions, asOf, code, plan)
    var budget = null, source = detail.budget
    if (source && source.budgeted_spending_cents > 0) {
      var days = new Date(asOf.getFullYear(), asOf.getMonth() + 1, 0).getDate()
      var spent = Model.fromMinor(source.actual_spending_cents, code), total = Model.fromMinor(source.budgeted_spending_cents, code)
      budget = {spent: spent, total: total, pace: Model.pace(spent, total, asOf.getDate(), days)}
    }
    var warnings = []
    if (String(base.cash.as_of).slice(0, 10) !== Model.iso(new Date())) warnings.push({key: "warn.timezone", arg: String(base.cash.as_of).slice(0, 10)})
    if (revenue.truncated) warnings.push({key: "warn.truncated", arg: String(root.maxPages * 100)})
    busy = false
    errorKey = ""
    updatedAt = new Date()
    now = updatedAt
    payload = {
      status: "ok", reason: "", currency: code, series: series, warnings: warnings,
      business: {series: revenue.series, skipped: revenue.skipped, recent: revenue.transactions.slice(0, 6).map(recentRow)}, game: currentGame,
      netWorth: Model.num(base.sheet.net_worth.amount), budget: budget,
      categories: lines.map(function(line) {
        var item = categories[line.id] || line
        return {name: String(line.category ? line.category.name : "").slice(0, 60), total: Model.fromMinor(line.budgeted_spending_cents, code),
          spent: Model.fromMinor(item.actual_spending_cents, code)}
      }),
      recent: (base.recent.transactions || []).map(recentRow)
    }
    announce(previousGame, currentGame)
  }

  function notify(title, body) {
    lastNotice = title + " | " + body
    if (!silent) Quickshell.execDetached(["notify-send", "-a", "Sure", title, body])
  }
  // Waits for the notification, so a second entry replaces the earlier undo offer.
  function notifyEntry(title, body) {
    lastNotice = title + " | " + body
    if (!silent) entryNotice.exec(["notify-send", "-a", "Sure", "-t", "8000", "-A", "undo=" + t("action.undo"), title, body])
  }
  function flushNotice() {
    if (pendingNotice) notifyEntry(t("notice.saved"), pendingNotice)
    pendingNotice = ""
  }

  function goalNotice(before, after) {
    var was = before ? before.goal : null, goal = after.goal
    if (!was || !goal || was.target !== goal.target || before.monthKey !== after.monthKey) return ""
    if (goal.reached && !was.reached) return t("notice.goal").arg(money(goal.target))
    return goal.passed > was.passed ? t("notice.stage").arg(money(goal.stages[goal.passed - 1])) : ""
  }

  // Quick entries get the race result; imports and other writes only announce real events.
  function announce(before, after) {
    var fresh = Model.freshAchievements(before, after)
    var record = !!before && after.isRecord && !before.isRecord
    var title = goalNotice(before, after) || (fresh.length ? t("notice.milestone").arg(winTitle(fresh[fresh.length - 1])) : record ? t("notice.record") : "")
    if (pendingNotice) notifyEntry(title || t("notice.saved"), pendingNotice + " · " + raceText(after))
    else if (title) notify(title, raceText(after))
    pendingNotice = ""
  }

  function ensureTags(names, index, ids, done) {
    if (index >= names.length) { done(ids); return }
    var lower = names[index].toLowerCase()
    var known = tags.filter(function(tag) { return String(tag.name).toLowerCase() === lower })[0]
    if (known) { ensureTags(names, index + 1, ids.concat([known.id]), done); return }
    api("POST", "/tags", {tag: {name: names[index]}}, function(ok, data, status) {
      if (!ok || !data || !data.id) { done(null, status); return }
      root.tags = root.tags.concat([data])
      ensureTags(names, index + 1, ids.concat([data.id]), done)
    })
  }

  function writeError(data, status) {
    if (status === 403) return t("error.read-only")
    if (data && data.message) return String(data.message).slice(0, 160)
    return t(errorFor(status)).replace("%1", String(status))
  }

  function addEntry(text, done) {
    if (saving) return
    var entry = Model.parseEntry(text, new Date(), businessTag)
    if (!entry.ok) { done(false, t("entry." + entry.error).replace("%1", entry.amount || "")); return }
    if (!payload || payload.status === "demo") { done(false, t("entry.demo")); return }
    var account = previewAccount(entry.account)
    if (!account) { done(false, t("entry.account-missing").replace("%1", entry.account)); return }
    saving = true
    api("GET", "/transactions?search=" + encodeURIComponent(entry.name) + "&per_page=25", null, function(ok, found) {
      var lower = entry.name.toLowerCase()
      var match = ok && found ? (found.transactions || []).filter(function(t) { return String(t.name).toLowerCase() === lower && t.category })[0] : null
      ensureTags(entry.tags, 0, [], function(tagIds, tagStatus) {
        if (tagIds === null) { saving = false; done(false, tagStatus === 403 ? t("error.read-only") : t("entry.tag-failed")); return }
        var transaction = {account_id: account.id, name: entry.name, date: entry.date, amount: entry.amount,
          nature: entry.nature, currency: account.currency, tag_ids: tagIds}
        if (match) transaction.category_id = match.category.id
        api("POST", "/transactions", {transaction: transaction}, function(saved, data, status) {
          saving = false
          if (!saved || !data || !data.id) { done(false, writeError(data, status)); return }
          lastAdded = {id: data.id, name: entry.name, amount: entry.amount, nature: entry.nature}
          var summary = (entry.nature === "income" ? "+" : "−") + plainMoney(entry.amount, account.currency) + " · " + entry.name
          var lowerBusiness = businessTag.toLowerCase()
          var revenue = entry.nature === "income" && (trackAllIncome || entry.tags.some(function(tag) { return tag.toLowerCase() === lowerBusiness }))
          if (revenue) pendingNotice = summary
          else notifyEntry(t("notice.saved"), summary)
          refresh()
          settle.restart()
          done(true, summary)
        })
      })
    })
  }

  function undoLast(done) {
    if (saving || !lastAdded) return
    saving = true
    var name = lastAdded.name
    api("DELETE", "/transactions/" + encodeURIComponent(lastAdded.id), null, function(ok, data, status) {
      saving = false
      if (ok) { lastAdded = null; notify(t("notice.removed"), name); refresh(); settle.restart() }
      else setError(status)
      if (done) done(ok)
    })
  }

  // Verifies the key against Sure before storing it, so a typo never replaces a working key.
  function connect(rawKey) {
    var key = String(rawKey || "").trim()
    if (connecting) return
    setupError = ""
    if (!/^[\x21-\x7e]{8,512}$/.test(key)) { setupError = "setup.bad-key"; return }
    connecting = true
    api("GET", "/accounts?per_page=1", null, function(ok, data, status) {
      if (!ok) {
        connecting = false
        setupError = status === 401 || status === 403 ? "setup.rejected" : errorFor(status)
        errorArg = String(status)
        return
      }
      keyWriter.pending = key
      keyWriter.running = true
    }, key)
  }

  // Goals are local, so changing one redraws at once and needs no trip to Sure.
  function rebuildGame() {
    if (!payload) return
    if (payload.status === "demo") {
      var key = errorKey, arg = errorArg
      showDemo(payload.reason)
      errorKey = key
      errorArg = arg
    } else if (gameSource) {
      var next = Object.assign({}, payload)
      next.game = Model.game(gameSource.transactions, gameSource.asOf, gameSource.currency, plan)
      payload = next
    }
  }
  function savePlan(next) {
    plan = next
    planWriter.exec(["sh", "-c", 'umask 077; mkdir -p "$1" && printf %s "$3" > "$2.tmp" && mv "$2.tmp" "$2"', "sh", configDir, configDir + "/plan.json", JSON.stringify(next)])
    rebuildGame()
  }
  function runCommand(command) {
    if (!game) return
    if (command.kind === "goal") savePlan(Model.setGoal(plan, game.monthKey, command.off ? null : command.amount, currency))
    else if (command.off) savePlan(Model.clearAction(plan, game.week))
    else savePlan(Model.setAction(plan, game.week, command.target, command.text))
  }
  function bumpAction(delta) {
    if (game && game.action && !game.action.demo) savePlan(Model.bumpAction(plan, game.week, delta))
  }
  function dismissReview() {
    if (!game || !game.review) return
    var next = Model.clone(plan)
    next.reviewed = game.review.key
    savePlan(next)
  }

  function toggleAmounts() {
    amountsHidden = !amountsHidden
    prefsWriter.exec(["sh", "-c", 'umask 077; mkdir -p "$1" && printf %s "$3" > "$2"', "sh", configDir, configDir + "/hide-amounts", amountsHidden ? "1" : "0"])
  }

  function openWeb(path) { if (baseUrl) Quickshell.execDetached(["omarchy-launch-webapp", baseUrl + path]) }
  function openSure() {
    if (!baseUrl) return
    var host = baseUrl.replace(/^https?:\/\//, "").replace(/:\d+$/, "")
    Quickshell.execDetached(["omarchy-launch-or-focus-webapp", "chrome-" + host + "__-Default", baseUrl])
  }
  function openImport() { openWeb("/imports") }
  function openApiKeys() { openWeb("/settings/api_keys") }
}
