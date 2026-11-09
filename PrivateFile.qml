import Quickshell.Io

// Writes a file only you can read, atomically and one write at a time. The last save wins.
Process {
  id: root
  property string path: ""
  property string current: ""
  property string queued: ""
  property bool hasQueued: false
  signal saved(bool ok)
  stdinEnabled: true
  command: ["sh", "-c", 'umask 077; mkdir -p "$(dirname "$1")" && cat > "$1.tmp" && mv "$1.tmp" "$1"', "sh", path]
  onStarted: { write(current); stdinEnabled = false }
  onExited: function(code) {
    stdinEnabled = true
    saved(code === 0)
    if (hasQueued) { hasQueued = false; begin(queued) }
  }
  function begin(text) { current = text; running = true }
  function save(text) {
    if (running) { queued = text; hasQueued = true }
    else begin(text)
  }
}
