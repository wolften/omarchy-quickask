// Helpers for wolften.quickask: clean agent CLI output for display in the
// popup. Agent CLIs may print ANSI colors, spinner rewrites (\r) and a
// session banner (e.g. opencode's "> build · model") — none of which should
// reach the chat view.
//
// Plain script (no QML imports) so it can be unit-tested with node.

function stripAnsi(value) {
  var s = String(value || "")
  // OSC sequences: ESC ] ... (BEL | ESC \)
  s = s.replace(/\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)/g, "")
  // CSI sequences: ESC [ params final-byte
  s = s.replace(/\x1b\[[0-9;?]*[A-Za-z]/g, "")
  // Charset / misc escapes: ESC ( B, ESC =, ESC >, ESC [ stray, lone ESC
  s = s.replace(/\x1b\([0-9A-B]/g, "")
  s = s.replace(/\x1b[=>]/g, "")
  // Buffer is cumulative during streaming: a chunk may end mid-sequence.
  // Drop the incomplete tail (next chunk completes it) so no stray
  // "[" or "]..." flashes on screen.
  s = s.replace(/\x1b\][^\x07\x1b]*$/g, "")
  s = s.replace(/\x1b\[[0-9;?]*$/g, "")
  s = s.replace(/\x1b\($/g, "")
  s = s.replace(/\x1b/g, "")
  // Spinner rewrites: keep only what follows the last \r on each line.
  s = s.replace(/\r\n/g, "\n")
  var lines = s.split("\n")
  for (var i = 0; i < lines.length; i++) {
    var parts = lines[i].split("\r")
    lines[i] = parts[parts.length - 1]
  }
  // Drop other control chars but keep \n and \t.
  s = lines.join("\n").replace(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g, "")
  return s
}

// Session banner some CLIs print before the answer, e.g. opencode's
// "> build · model" on stderr (kept here in case an agent puts it on
// stdout). Only matches leading lines so markdown quotes in the answer
// are never touched.
function isBannerLine(line) {
  return /^>\s+\S.*·.*$/.test(line)
}

// Model id from a banner line: everything after "·".
function bannerModel(line) {
  if (!isBannerLine(line)) return ""
  var parts = String(line).split("·")
  return parts.length > 1 ? parts.slice(1).join("·").trim() : ""
}

function findBannerModel(raw) {
  var lines = stripAnsi(raw).split("\n")
  for (var i = 0; i < lines.length; i++) {
    var model = bannerModel(lines[i])
    if (model !== "") return model
  }
  return ""
}

function cleanStream(raw, isFinal) {
  var stripped = stripAnsi(raw)
  var lines = stripped.split("\n")
  var start = 0
  while (start < lines.length && (lines[start].trim() === "" || isBannerLine(lines[start]))) {
    start++
  }
  var end = lines.length
  while (end > start && lines[end - 1].trim() === "") {
    end--
  }
  // Mid-stream the buffer rarely ends on a line boundary: a trailing
  // "> ..." line may be a session banner still forming. Hold it back
  // until it completes (final buffers always render it properly).
  if (!isFinal && end > start && !/\n$/.test(stripped) && /^>/.test(lines[end - 1])) {
    end--
  }
  return lines.slice(start, end).join("\n")
}

function lastErrorLines(raw, count) {
  var n = count || 3
  var lines = stripAnsi(raw).split("\n").filter(function(l) { return l.trim() !== "" })
  return lines.slice(-n).join("\n")
}

// Detects a permission denial inside an answer body (agent CLIs report
// rejections inline on stdout, e.g. opencode's "[Error: The user rejected
// permission to use this specific tool call.]").
function hasPermissionDenial(text) {
  return /reject.*permission|permission.*reject|permission to use|permission denied/i.test(String(text || ""))
}

function permissionHint() {
  return "Dica: o modo rápido não aprova permissões — para ações em arquivos, abra no terminal (botão superior)."
}

function withPermissionHint(answer) {
  var body = String(answer || "")
  if (body !== "" && hasPermissionDenial(body) && body.indexOf(permissionHint()) === -1) {
    return body + "\n\n[" + permissionHint() + "]"
  }
  return body
}

// Like lastErrorLines, but ignores session banners: agent CLIs (notably
// opencode) always print a banner on stderr, which is not an error.
function cleanError(raw, count) {
  var n = count || 3
  var lines = stripAnsi(raw).split("\n").filter(function(l) {
    return l.trim() !== "" && !isBannerLine(l)
  })
  return lines.slice(-n).join("\n")
}

if (typeof module !== "undefined") {
  module.exports = {
    stripAnsi: stripAnsi,
    isBannerLine: isBannerLine,
    bannerModel: bannerModel,
    findBannerModel: findBannerModel,
    cleanStream: cleanStream,
    lastErrorLines: lastErrorLines,
    cleanError: cleanError,
    hasPermissionDenial: hasPermissionDenial,
    permissionHint: permissionHint,
    withPermissionHint: withPermissionHint
  }
}
