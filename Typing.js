// Compose dead keys inside the viewer. Separate wtype processes do not share a
// keyboard device, so relying on the target app to remember a dead key is fragile.
var deadMarks = {
  dead_acute: "\u0301", dead_grave: "\u0300", dead_circumflex: "\u0302",
  dead_tilde: "\u0303", dead_diaeresis: "\u0308", dead_cedilla: "\u0327",
  dead_caron: "\u030c", dead_breve: "\u0306", dead_abovering: "\u030a",
  dead_macron: "\u0304", dead_doubleacute: "\u030b", dead_ogonek: "\u0328",
  dead_abovedot: "\u0307", dead_belowdot: "\u0323"
}

var spacingMarks = {
  dead_acute: "´", dead_grave: "`", dead_circumflex: "^",
  dead_tilde: "~", dead_diaeresis: "¨", dead_cedilla: "¸",
  dead_caron: "ˇ", dead_breve: "˘", dead_abovering: "˚",
  dead_macron: "¯", dead_doubleacute: "˝", dead_ogonek: "˛",
  dead_abovedot: "˙", dead_belowdot: "·"
}

function spacing(deadSymbol) {
  return spacingMarks[deadSymbol] || ""
}

function compose(deadSymbol, character) {
  var mark = deadMarks[deadSymbol]
  if (!mark) return null
  if (character === " ") return spacing(deadSymbol)
  return (character + mark).normalize("NFC")
}

function accents(character) {
  if (!character || character.length !== 1 || character.toLowerCase() === character.toUpperCase()) return []
  var deadKeys = ["dead_acute", "dead_grave", "dead_circumflex", "dead_diaeresis",
    "dead_tilde", "dead_abovering", "dead_macron", "dead_cedilla", "dead_caron"]
  var choices = []
  for (var i = 0; i < deadKeys.length; i++) {
    var composed = compose(deadKeys[i], character)
    if (composed.length === 1 && composed !== character && choices.indexOf(composed) === -1)
      choices.push(composed)
  }
  return choices
}

if (typeof module !== "undefined") {
  module.exports = { spacing: spacing, compose: compose, accents: accents }
}
