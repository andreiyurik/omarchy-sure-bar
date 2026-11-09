// Starts tests/harness/shell.qml in headless Quickshell and collects what it printed.
const fs = require("fs"), os = require("os"), path = require("path"), {spawn} = require("child_process")

const repo = path.join(__dirname, "..", "..")
const work = fs.mkdtempSync(path.join(os.tmpdir(), "sure-bar-test-"))
const shell = path.join(work, "shell")
fs.cpSync(__dirname, shell, {recursive: true})
fs.mkdirSync(path.join(shell, "plugin"))
for (const file of fs.readdirSync(repo)) if (/\.(qml|js)$/.test(file)) fs.copyFileSync(path.join(repo, file), path.join(shell, "plugin", file))

function newHome(key) {
  const home = fs.mkdtempSync(path.join(work, "home-")), dir = path.join(home, ".config/sure-bar")
  fs.mkdirSync(dir, {recursive: true, mode: 0o700})
  if (key) fs.writeFileSync(path.join(dir, "api-key"), key + "\n", {mode: 0o600})
  return home
}
const file = (home, name) => path.join(home, ".config/sure-bar", name)

// `wrap` turns the qs command into another one, for example to run it in a private namespace.
function run(home, settings, steps, env = {}, {wrap, limitMs = 20000} = {}) {
  return new Promise((resolve, reject) => {
    const command = ["qs", "-p", shell], [program, ...args] = wrap ? wrap(command) : command
    const child = spawn(program, args, {env: {...process.env, HOME: home, XDG_CONFIG_HOME: path.join(home, ".config"), QT_QPA_PLATFORM: "offscreen", SETTINGS: JSON.stringify(settings), STEPS: JSON.stringify(steps), ...env}})
    let output = ""
    child.stdout.on("data", d => { output += d }); child.stderr.on("data", d => { output += d })
    const timer = setTimeout(() => { output += "\nHARNESS TIMEOUT"; child.kill("SIGKILL") }, limitMs)
    child.on("close", () => {
      clearTimeout(timer)
      const states = {}, callbacks = {}
      for (const m of output.matchAll(/STATE (\{.*\})/g)) { const v = JSON.parse(m[1]); states[v.label] = v.data }
      for (const m of output.matchAll(/CALLBACK (\{.*\})/g)) { const v = JSON.parse(m[1]); callbacks[v.label] = v }
      const problem = output.match(/.*(TypeError|ReferenceError|Unable to assign|is not a function|is not defined).*/)
      if (output.includes("HARNESS TIMEOUT")) return reject(new Error("harness timed out\n" + output.slice(-1500)))
      if (problem) return reject(new Error("QML error: " + problem[0]))
      const stepFailed = output.match(/STEPFAILED .*/)
      if (stepFailed) return reject(new Error(stepFailed[0]))
      resolve({states, callbacks, output})
    })
  })
}
const cleanup = () => fs.rmSync(work, {recursive: true, force: true})

module.exports = {work, newHome, file, run, cleanup}
