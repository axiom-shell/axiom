import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "GreeterUsers"

  readonly property string passwd: ["root:x:0:0::/root:/usr/bin/zsh", "bin:x:1:1::/:/usr/bin/nologin", "greeter:x:962:962:greetd greeter user:/:/bin/bash", "zoe:x:1001:1001:Zoe Q,,,:/home/zoe:/bin/bash", "amy:x:1000:1000::/home/amy:/usr/bin/fish", "locked:x:1002:1002::/home/locked:/usr/bin/false", "nobody:x:65534:65534:Kernel Overflow User:/:/usr/bin/nologin", "# a comment", "broken line", ""].join("\n")

  function test_uid_range() {
    compare(GreeterUsers.uidRange("# x\nUID_MIN\t\t\t 1000\nUID_MAX\t\t60000\nSYS_UID_MIN 500"), {
      "min": 1000,
      "max": 60000
    });
    compare(GreeterUsers.uidRange("UID_MIN 2000"), {
      "min": 2000,
      "max": 60000
    });
    compare(GreeterUsers.uidRange(""), {
      "min": 1000,
      "max": 60000
    });
  }

  function test_parse_keeps_regular_users_by_name() {
    const users = GreeterUsers.parse(passwd, GreeterUsers.uidRange(""));
    compare(users.map(user => user.name), ["amy", "zoe"]);
    compare(users[0].realName, "amy");
    compare(users[1].realName, "Zoe Q");
    compare(users[1].uid, 1001);
    compare(users[1].home, "/home/zoe");
  }

  function test_find() {
    const users = GreeterUsers.parse(passwd, GreeterUsers.uidRange(""));
    compare(GreeterUsers.find(users, " zoe ").realName, "Zoe Q");
    // Not listed: still a user, greetd decides
    compare(GreeterUsers.find(users, "ldapuser").name, "ldapuser");
    compare(GreeterUsers.find(users, "ldapuser").uid, -1);
    compare(GreeterUsers.find(users, "  "), null);
  }
}
