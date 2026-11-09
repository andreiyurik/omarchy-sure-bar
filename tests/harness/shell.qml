import QtQuick
import Quickshell
import "plugin" as P

// Runs the real Service.qml through a list of steps and prints what it did. See tests/service.test.js.
ShellRoot {
  id: h
  property var steps: JSON.parse(Quickshell.env("STEPS"))
  property int index: -1
  property bool waiting: false

  P.Service { id: s; silent: true; overrides: JSON.parse(Quickshell.env("SETTINGS")) }

  function idle() {
    return s.keyChecked && s.snapshotChecked && !s.busy && !s.saving && !s.connecting && !s.probing && !!(s.payload || s.needsSetup)
  }
  function snapshot() {
    var p = s.payload, g = s.game
    return {at: Date.now(), status: p ? p.status : null, demo: s.isDemo, errorKey: s.errorKey, errorArg: s.errorArg, setupReason: s.setupReason, setupError: s.setupError,
      readOnly: s.readOnly, hasKey: s.hasKey, baseUrl: s.baseUrl, notice: s.lastNotice, current: g ? g.current : null, total: g ? g.total : null,
      goal: g && g.goal ? g.goal.target : null, warnings: p ? (p.warnings || []).map(function(w) { return w.key }) : [], zone: s.visibleTimezoneNote ? s.visibleTimezoneNote.dismiss : "",
      updatedAt: s.updatedAt.getTime(), recent: p && p.recent ? p.recent.length : 0, bizRecent: p && p.business && p.business.recent ? p.business.recent.length : 0,
      retryAttempt: s.retryAttempt, blocked: s.blockedUntil > Date.now(), retrying: s.canRetry}
  }
  function next() { waiting = false; index++; if (index >= steps.length) Qt.quit(); else run(steps[index]) }
  function run(step) {
    if (step === "idle") { waiting = true; pending = function() { return h.idle() }; return }
    if (step.until) { var check = Function("s", "return " + step.until); waiting = true; pending = function() { return check(s) }; return }
    if (step.state) { console.log("STATE " + JSON.stringify({label: step.state, data: snapshot()})); next(); return }
    if (step.wait) { waitTimer.interval = step.wait; waitTimer.start(); return }
    if (step.http) {
      var x = new XMLHttpRequest()
      x.onreadystatechange = function() { if (x.readyState === XMLHttpRequest.DONE) { if (x.status < 200 || x.status >= 300) console.log("STEPFAILED " + x.status + " " + step.http.url); h.next() } }
      x.open(step.http.method || "POST", step.http.url)
      x.setRequestHeader("User-Agent", "sure-bar-tests")
      x.send(step.http.body ? JSON.stringify(step.http.body) : "")
      return
    }
    if (step.call) {
      var args = (step.args || []).slice()
      if (step.callback) {
        args.push(function(ok, text) { console.log("CALLBACK " + JSON.stringify({label: step.callback, ok: ok, text: text})); h.next() })
        s[step.call].apply(s, args)
      } else { s[step.call].apply(s, args); next() }
    }
  }
  property var pending: null
  Timer { id: waitTimer; onTriggered: h.next() }
  Timer { interval: 15; repeat: true; running: h.waiting; onTriggered: if (h.pending && h.pending()) h.next() }
  Timer { interval: 25; running: true; onTriggered: h.next() }
}
