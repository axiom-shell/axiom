import QtQuick
import QtTest
import qs.components.methods

// SwayConf: quoting a sway command's argument.
TestCase {
  id: test
  name: "SwayConf"

  // Records the helpers' calls as shared fixtures for the axiom binary
  Shared {
    id: shared
    testCase: test
  }

  function test_quote() {
    compare(shared.calls.SwayConf.quote("DP-1"), "DP-1");
    compare(shared.calls.SwayConf.quote("AOC CU34G4Z XJ9"), "\"AOC CU34G4Z XJ9\"");
    // Sway keeps a backslash before a quote, so a `"` is single-quoted
    compare(shared.calls.SwayConf.quote("say \"hi\""), "\"say \"'\"'\"hi\"'\"'");
    compare(shared.calls.SwayConf.quote("\""), "'\"'");
    compare(shared.calls.SwayConf.quote(""), "\"\"");
    compare(shared.calls.SwayConf.quote("it's"), "\"it's\"");
  }
}
