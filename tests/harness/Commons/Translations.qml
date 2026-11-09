import QtQuick

// Returns keys instead of text, so tests assert on meaning rather than wording.
QtObject {
  property url directory
  function t(key) { return key }
  function tn(key, count) { return key }
}
