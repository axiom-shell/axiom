pragma Singleton
import QtQuick

// The launcher's file mode (LauncherFiles): what text typed after ~ asks
// for, and the text that types a path back. `home` is $HOME without a
// trailing slash, passed in. No file access: the daemon reads the disk.
QtObject {
  id: root

  // What `text` (the search text, starting with ~) asks for:
  //   "~"         { kind: "recent" }                  the recent files
  //   "~rep"      { kind: "search", dir: "", query: "rep" }   every root
  //   "~/a/"      { kind: "browse", dir: home/a, query: "" }  a's entries
  //   "~/a/rep"   { kind: "search", dir: home/a, query: "rep" } below a
  // `typed` is the folder as typed ("~/a/"), "" for none. A folder's . and
  // .. are resolved ("~/../" is home's parent); spaces around the query are
  // dropped, those inside kept (each word must match)
  function parse(text, home) {
    const body = String(text ?? "").replace(/^\s*~/, "");
    if (!body.startsWith("/")) {
      const query = body.trim();
      return query === "" ? {
        "kind": "recent",
        "dir": "",
        "typed": "",
        "query": ""
      } : {
        "kind": "search",
        "dir": "",
        "typed": "",
        "query": query
      };
    }
    const slash = body.lastIndexOf("/");
    const typed = "~" + body.slice(0, slash + 1);
    const query = body.slice(slash + 1).trim();
    return {
      "kind": query === "" ? "browse" : "search",
      "dir": root.join(home, body.slice(0, slash)),
      "typed": typed,
      "query": query
    };
  }

  // `dir` and `rel` joined, with . and .. resolved and no trailing or
  // doubled slash; "/" at most up to the root
  function join(dir, rel) {
    const parts = [];
    (String(dir ?? "") + "/" + String(rel ?? "")).split("/").forEach(part => {
      if (part === "" || part === ".")
        return;
      if (part === "..")
        parts.pop();
      else
        parts.push(part);
    });
    return "/" + parts.join("/");
  }

  // `path` (absolute) as text typed after ~: "~/a/b" below home, else
  // through ".." ("~/../../mnt/x"); a folder ends in "/" (Tab lists it)
  function completion(path, home, isDir) {
    const target = root.join(path, "");
    const base = root.join(home, "");
    const tail = isDir && target !== "/" ? "/" : "";
    if (target === base)
      return "~/";
    if (base === "/" || target.startsWith(base + "/"))
      return "~/" + target.slice(base === "/" ? 1 : base.length + 1) + tail;
    // Up from home to the deepest folder both are in
    const from = base.split("/").slice(1);
    const to = target.split("/").slice(1);
    let same = 0;
    while (same < from.length && same < to.length && from[same] === to[same])
      same++;
    const up = from.slice(same).map(() => "..");
    return "~/" + up.concat(to.slice(same)).join("/") + tail;
  }

  // The folder holding `path` ("/" for the root's entries)
  function parentOf(path) {
    return root.join(path, "..");
  }

  // Whether a file of `mime` may have a thumbnail: axiom makes them for
  // images, and a file manager's for videos and PDFs are reused
  function thumbnailable(mime) {
    const m = String(mime ?? "");
    return m.startsWith("image/") || m.startsWith("video/") || m === "application/pdf";
  }
}
