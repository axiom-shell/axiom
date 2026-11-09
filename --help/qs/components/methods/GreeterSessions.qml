pragma Singleton
import QtQuick

// The sessions the greeter can start (GreetdManager): Wayland session
// desktop entries (wayland-sessions/*.desktop in each data dir), their Exec line
// split into the argv greetd launches, and the environment they start in.
QtObject {
  id: root

  // A desktop entry's text as a session, or null when it isn't one to
  // show (no Exec, Hidden or NoDisplay). `id` is its file name without
  // .desktop. { id, name, comment, exec (argv), desktopNames }
  function parse(text, id) {
    const values = {};
    let inEntry = false;
    for (const raw of String(text ?? "").split("\n")) {
      const line = raw.trim();
      if (line.startsWith("[")) {
        inEntry = line === "[Desktop Entry]";
        continue;
      }
      const eq = line.indexOf("=");
      if (!inEntry || eq <= 0 || line.startsWith("#"))
        continue;
      const key = line.slice(0, eq).trim();
      // Localized keys (Name[de]) are left out: the greeter shows the
      // entry's own name
      if (!(key in values))
        values[key] = line.slice(eq + 1).trim();
    }
    const exec = root.execArgv(values.Exec ?? "");
    if (exec.length === 0 || values.Hidden === "true" || values.NoDisplay === "true")
      return null;
    return {
      "id": id,
      "name": values.Name || id,
      "comment": values.Comment ?? "",
      "exec": exec,
      "desktopNames": (values.DesktopNames ?? "").split(";").filter(name => name !== "")
    };
  }

  // An Exec value as argv, by the desktop entry spec: words split at
  // spaces, double quotes group (with \" \` \$ \\ escaped inside), field
  // codes (%f, %U, …) dropped and %% kept as %
  function execArgv(exec) {
    const args = [];
    let word = "";
    let started = false;
    let quoted = false;
    const text = String(exec ?? "");
    for (let i = 0; i < text.length; i++) {
      const c = text[i];
      if (quoted) {
        if (c === "\\" && i + 1 < text.length && "\"`$\\".includes(text[i + 1]))
          word += text[++i];
        else if (c === "\"")
          quoted = false;
        else
          word += c;
      } else if (c === "\"") {
        quoted = true;
        started = true;
      } else if (c === " " || c === "\t") {
        if (started)
          args.push(word);
        word = "";
        started = false;
      } else {
        word += c;
        started = true;
      }
    }
    if (started)
      args.push(word);
    return args.filter(arg => !/^%[a-zA-Z]$/.test(arg)).map(arg => arg.replace(/%%/g, "%"));
  }

  // Of the desktop entry files found (paths, from the data dirs in lookup
  // order), the one each id is read from: the first, as an entry in a more
  // important dir replaces (or, Hidden, removes) one of the same name.
  // [{ id, file }]
  function files(paths) {
    const seen = {};
    return (paths ?? []).map(path => ({
          "id": String(path).replace(/^.*\//, "").replace(/\.desktop$/, ""),
          "file": String(path)
        })).filter(entry => {
      if (seen[entry.id])
        return false;
      seen[entry.id] = true;
      return true;
    });
  }

  // Sessions by name
  function sorted(sessions) {
    return (sessions ?? []).filter(session => !!session).sort((a, b) => a.name.localeCompare(b.name));
  }

  // The environment a session starts in (greetd's start_session env)
  function environment(session) {
    const desktops = session.desktopNames.length > 0 ? session.desktopNames : [session.name];
    return ["XDG_SESSION_TYPE=wayland", "XDG_CURRENT_DESKTOP=" + desktops.join(":"), "XDG_SESSION_DESKTOP=" + session.id];
  }
}
