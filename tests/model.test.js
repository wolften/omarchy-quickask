const test = require("node:test")
const assert = require("node:assert")
const M = require("../QuickAskModel.js")

test("stripAnsi removes CSI colors", () => {
  assert.equal(M.stripAnsi("\x1b[0mOK\x1b[0m"), "OK")
  assert.equal(M.stripAnsi("\x1b[1;32mhello\x1b[0m world"), "hello world")
})

test("stripAnsi keeps text after carriage-return spinner rewrites", () => {
  assert.equal(M.stripAnsi("⠋ thinking\r⠙ still\rDone"), "Done")
  assert.equal(M.stripAnsi("a\r\nb"), "a\nb")
})

test("cleanStream drops leading banners and blank lines", () => {
  const raw = "\x1b[0m\n> build · muse-spark-1.3\n\x1b[0m\nHello\nworld\n\n"
  assert.equal(M.cleanStream(raw, true), "Hello\nworld")
})

test("cleanStream preserves markdown quotes in the final render", () => {
  const raw = "Intro\n> quoted text\n> more quote"
  assert.equal(M.cleanStream(raw, true), raw)
})

test("cleanStream holds back a trailing partial banner mid-stream", () => {
  assert.equal(M.cleanStream("Hello\n> bu", false), "Hello")
  assert.equal(M.cleanStream("Hello\n> build · m", false), "Hello")
  assert.equal(M.cleanStream("Hello\nworld\n", false), "Hello\nworld")
})

test("stripAnsi drops incomplete trailing sequences (streaming chunks)", () => {
  assert.equal(M.stripAnsi("abc\x1b["), "abc")
  assert.equal(M.stripAnsi("abc\x1b[1;"), "abc")
  assert.equal(M.stripAnsi("abc\x1b]0;title"), "abc")
  assert.equal(M.stripAnsi("abc\x1b"), "abc")
})

test("cleanStream of empty input is empty", () => {
  assert.equal(M.cleanStream(""), "")
  assert.equal(M.cleanStream("\n\n"), "")
})

test("lastErrorLines returns tail of non-blank lines", () => {
  const raw = "a\nb\nc\nd\n"
  assert.equal(M.lastErrorLines(raw, 2), "c\nd")
  assert.equal(M.lastErrorLines("", 3), "")
})

test("bannerModel extracts model from session banner", () => {
  assert.equal(M.bannerModel("> build · muse-spark-1.3"), "muse-spark-1.3")
  assert.equal(M.bannerModel("plain text"), "")
  assert.equal(M.findBannerModel("\x1b[0m\n> build · muse-spark-1.3\n\x1b[0m\n"), "muse-spark-1.3")
  assert.equal(M.findBannerModel("no banner here"), "")
})

test("cleanError ignores session banners", () => {
  const raw = "\x1b[0m\n> build · muse-spark-1.3\n\x1b[0m\n"
  assert.equal(M.cleanError(raw, 3), "")
  assert.equal(M.cleanError("banner\n> build · x\nreal error\n", 3), "banner\nreal error")
})

test("withPermissionHint appends hint on denial", () => {
  const denied = "Vou ler o arquivo.\n[Error: The user rejected permission to use this specific tool call.]"
  const out = M.withPermissionHint(denied)
  assert.ok(out.includes("Dica: o modo rápido"))
  assert.equal(M.withPermissionHint(out), out)
  assert.equal(M.withPermissionHint("Resposta normal."), "Resposta normal.")
})
