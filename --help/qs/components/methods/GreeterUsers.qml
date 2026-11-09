pragma Singleton
import QtQuick

// The people the greeter offers to log in (GreetdManager): accounts from
// /etc/passwd whose uid is in /etc/login.defs' UID_MIN..UID_MAX (regular
// users, not system accounts) and whose shell lets them log in.
QtObject {
  id: root

  readonly property var _noLogin: ["nologin", "false"]

  // UID_MIN and UID_MAX from login.defs' text, else the usual 1000..60000.
  // { min, max }
  function uidRange(loginDefs) {
    const read = (key, fallback) => {
      const match = String(loginDefs ?? "").match(new RegExp(`^\\s*${key}\\s+(\\d+)`, "m"));
      return match ? Number(match[1]) : fallback;
    };
    return {
      "min": read("UID_MIN", 1000),
      "max": read("UID_MAX", 60000)
    };
  }

  // passwd's text as users, by name: { name, uid, realName (the GECOS
  // field's first part, else the name), home, shell }
  function parse(passwd, range) {
    const users = [];
    for (const line of String(passwd ?? "").split("\n")) {
      const fields = line.split(":");
      if (fields.length < 7 || line.startsWith("#"))
        continue;
      const uid = Number(fields[2]);
      const shell = fields[6].trim();
      const shellName = shell.replace(/^.*\//, "");
      if (!Number.isInteger(uid) || uid < range.min || uid > range.max || !shell || root._noLogin.includes(shellName))
        continue;
      const realName = fields[4].split(",")[0].trim();
      users.push({
        "name": fields[0],
        "uid": uid,
        "realName": realName || fields[0],
        "home": fields[5],
        "shell": shell
      });
    }
    return users.sort((a, b) => a.name < b.name ? -1 : a.name > b.name ? 1 : 0);
  }

  // A typed name as a user: one of `users`, else a bare one (an account
  // the list leaves out, an LDAP user: greetd decides)
  function find(users, name) {
    const typed = String(name ?? "").trim();
    return (users ?? []).find(user => user.name === typed) ?? (typed ? {
        "name": typed,
        "uid": -1,
        "realName": typed,
        "home": "",
        "shell": ""
      } : null);
  }
}
