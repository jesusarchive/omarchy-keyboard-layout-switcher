const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

// Exercise the actual QML methods without starting processes or a compositor.
// This does not evaluate QML bindings or replace a runtime smoke test.
module.exports = function qmlFunctions(file, state) {
  const source = fs.readFileSync(path.join(__dirname, "..", file), "utf8")
  const context = vm.createContext(state)
  const functions = source.match(/^  function \w+\([^\n]*\{(?:[^\n]*\}$|\n[^]*?^  \})/gm) || []
  for (const method of functions) vm.runInContext(method, context)
  return context
}
