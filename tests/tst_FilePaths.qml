import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "FilePaths"

  readonly property string home: "/home/u"

  function test_parseRecentAndSearch() {
    compare(FilePaths.parse("~", home).kind, "recent");
    compare(FilePaths.parse("  ~   ", home).kind, "recent", "spaces alone are no query");
    compare(FilePaths.parse("~rep", home), {
      "kind": "search",
      "dir": "",
      "typed": "",
      "query": "rep"
    });
    compare(FilePaths.parse("~ my report ", home).query, "my report", "words inside are kept");
    compare(FilePaths.parse("~doc/rep", home), {
      "kind": "search",
      "dir": "",
      "typed": "",
      "query": "doc/rep"
    }, "a slash after a name is a segment of the pattern, not a folder");
  }

  function test_parseFolders() {
    compare(FilePaths.parse("~/", home), {
      "kind": "browse",
      "dir": "/home/u",
      "typed": "~/",
      "query": ""
    });
    compare(FilePaths.parse("~/Documents/", home), {
      "kind": "browse",
      "dir": "/home/u/Documents",
      "typed": "~/Documents/",
      "query": ""
    });
    compare(FilePaths.parse("~/Documents/rep", home), {
      "kind": "search",
      "dir": "/home/u/Documents",
      "typed": "~/Documents/",
      "query": "rep"
    });
    compare(FilePaths.parse("~/Doc", home), {
      "kind": "search",
      "dir": "/home/u",
      "typed": "~/",
      "query": "Doc"
    }, "a name not ended by a slash is searched for below its folder");
    compare(FilePaths.parse("~/../", home).dir, "/home", "..");
    compare(FilePaths.parse("~/../../../", home).dir, "/", "never above the root");
    compare(FilePaths.parse("~/a//./b/", home).dir, "/home/u/a/b");
    compare(FilePaths.parse("~/My Files/", home).dir, "/home/u/My Files", "spaces in a folder");
  }

  function test_join() {
    compare(FilePaths.join("/a/b", "c"), "/a/b/c");
    compare(FilePaths.join("/a/b/", "../c/"), "/a/c");
    compare(FilePaths.join("/", ""), "/");
    compare(FilePaths.join("/a", ".."), "/");
  }

  function test_completion() {
    compare(FilePaths.completion("/home/u/Documents", home, true), "~/Documents/", "a folder lists itself");
    compare(FilePaths.completion("/home/u/Documents/a.pdf", home, false), "~/Documents/a.pdf");
    compare(FilePaths.completion("/home/u", home, true), "~/");
    compare(FilePaths.completion("/home/u2/x", home, false), "~/../u2/x", "a sibling of home is not below it");
    compare(FilePaths.completion("/mnt/data", home, true), "~/../../mnt/data/");
    compare(FilePaths.completion("/", home, true), "~/../../");
    // What it types parses back to the folder
    compare(FilePaths.parse(FilePaths.completion("/mnt/data", home, true), home).dir, "/mnt/data");
  }

  function test_under() {
    verify(FilePaths.under("/home/u/a", ["/home/u"]));
    verify(FilePaths.under("/home/u", ["/home/u/"]), "a root itself");
    verify(!FilePaths.under("/home/u2", ["/home/u"]), "not a prefix of the name");
    verify(FilePaths.under("/etc", ["/srv", "/"]), "the root holds everything");
    verify(!FilePaths.under("/home/u", []));
  }

  function test_parentOf() {
    compare(FilePaths.parentOf("/home/u/a.txt"), "/home/u");
    compare(FilePaths.parentOf("/a"), "/");
  }

  function test_thumbnailable() {
    verify(FilePaths.thumbnailable("image/png"));
    verify(FilePaths.thumbnailable("video/mp4"));
    verify(FilePaths.thumbnailable("application/pdf"));
    verify(!FilePaths.thumbnailable("text/plain"));
    verify(!FilePaths.thumbnailable("inode/directory"));
    verify(!FilePaths.thumbnailable(undefined));
  }
}
