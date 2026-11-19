pragma Singleton
import QtQuick

// Stand-in for qs.config I18n in the layout harness (the real one imports
// Quickshell.Io): the English text with every `{n}` filled.
QtObject {
  function tr(text, ...args) {
    return args.reduce((out, arg, i) => out.split("{" + i + "}").join(arg), text);
  }

  function formatDate(date, format) {
    return "2026-01-01";
  }
}
