import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "SchemaLayout"

  RepoFiles {
    id: files
  }

  property var schema

  function initTestCase() {
    schema = files.json("config/json/config.schema.json");
  }

  function test_rows_flatten_and_skip_hidden() {
    const rows = SchemaLayout.rows({
      "properties": {
        "a": {
          "type": "string",
          "title": "A"
        },
        "hidden": {
          "type": "string",
          "x-settings": false
        },
        "group": {
          "type": "object",
          "properties": {
            "b": {
              "type": "boolean"
            }
          }
        },
        "empty": {
          "type": "object",
          "properties": {}
        },
        "list": {
          "type": "array",
          "items": {
            "properties": {
              "x": {
                "type": "string"
              }
            }
          }
        },
        "tags": {
          "type": "array",
          "items": {
            "type": "string"
          }
        }
      }
    }, ["S"]);
    compare(rows.map(r => r.kind + ":" + r.path.join(".")), ["field:S.a", "group:S.group", "field:S.group.b", "array:S.list", "field:S.tags"]);
  }

  function test_defaultAt() {
    const objectSchema = {
      "properties": {
        "size": {
          "type": "integer",
          "default": 4
        },
        "open": {
          "type": "object",
          "properties": {
            "onHover": {
              "type": "boolean",
              "default": false
            }
          }
        }
      }
    };
    const rows = [[["size"], 4, "a top-level default"], [["open", "onHover"], false, "a nested default, falsy kept"], [["open"], undefined, "an object with no default"], [["missing", "x"], undefined, "past a missing property"]];
    for (const [path, expected, message] of rows)
      compare(SchemaLayout.defaultAt(objectSchema, path), expected, message);
  }

  function test_failingKey() {
    const values = {
      "/$supports.blur": false,
      "/$compositor": "sway",
      "on": true
    };
    const valueOf = key => values[key];
    compare(SchemaLayout.failingKey(null, valueOf), "");
    compare(SchemaLayout.failingKey({
      "on": true,
      "/$supports.blur": true
    }, valueOf), "/$supports.blur");
    compare(SchemaLayout.failingKey({
      "/$compositor": "hyprland"
    }, valueOf), "/$compositor");
    compare(SchemaLayout.failingKey({
      "on": true,
      "/$compositor": "sway"
    }, valueOf), "");
  }

  function test_showIfHolds() {
    const values = {
      "mode": "grid",
      "on": true,
      "list": [1],
      "none": []
    };
    const valueOf = key => values[key];
    verify(SchemaLayout.showIfHolds(null, valueOf));
    verify(SchemaLayout.showIfHolds({
      "mode": "grid"
    }, valueOf));
    verify(!SchemaLayout.showIfHolds({
      "mode": "standard"
    }, valueOf));
    verify(SchemaLayout.showIfHolds({
      "mode": ["standard", "grid"]
    }, valueOf));
    verify(!SchemaLayout.showIfHolds({
      "mode": {
        "not": "grid"
      }
    }, valueOf));
    verify(!SchemaLayout.showIfHolds({
      "mode": "grid",
      "on": false
    }, valueOf));
    // notEmpty: a list with something in it
    verify(SchemaLayout.showIfHolds({
      "list": {
        "notEmpty": true
      }
    }, valueOf));
    verify(!SchemaLayout.showIfHolds({
      "none": {
        "notEmpty": true
      }
    }, valueOf));
    // anyOf: one of its conditions holds, alongside the other keys
    verify(SchemaLayout.showIfHolds({
      "anyOf": [
        {
          "mode": "standard"
        },
        {
          "mode": "grid",
          "on": true
        }
      ]
    }, valueOf));
    verify(!SchemaLayout.showIfHolds({
      "anyOf": [
        {
          "mode": "standard"
        },
        {
          "on": false
        }
      ]
    }, valueOf));
    verify(!SchemaLayout.showIfHolds({
      "on": false,
      "anyOf": [
        {
          "mode": "grid"
        }
      ]
    }, valueOf));
  }

  // The real settings page: every category has cards, and every
  // `x-showIf` names a sibling or a config path that exists
  function test_intro_on_the_sections_own_card() {
    const groups = SchemaLayout.groups({
      "properties": {
        "S": {
          "type": "object",
          "title": "Sec",
          "x-intro": "Status",
          "properties": {
            "a": {
              "type": "boolean",
              "title": "A"
            },
            "b": {
              "type": "boolean",
              "title": "B",
              "x-group": "Other"
            }
          }
        }
      }
    }, "S");
    compare(groups.length, 2, "no separate card");
    compare(groups[0].title, "Sec");
    compare(groups[0].intro, "Status");
    compare(groups[1].intro, "");
  }

  function test_intro_on_a_nested_objects_own_card() {
    const groups = SchemaLayout.groups({
      "properties": {
        "S": {
          "type": "object",
          "title": "Sec",
          "properties": {
            "a": {
              "type": "boolean",
              "title": "A"
            },
            "n": {
              "type": "object",
              "title": "Nested",
              "x-intro": "Status",
              "properties": {
                "b": {
                  "type": "boolean",
                  "title": "B"
                },
                "c": {
                  "type": "boolean",
                  "title": "C",
                  "x-group": "Other"
                }
              }
            }
          }
        }
      }
    }, "S");
    compare(groups.map(group => group.title), ["Sec", "Nested", "Other"]);
    compare(groups.map(group => group.intro), ["", "Status", ""]);
  }

  // A nested object with `x-group` joins that card under its own title,
  // its `x-showIf` on its group row and (from its parent) on its rows
  function test_object_joins_group_card() {
    const groups = SchemaLayout.groups({
      "properties": {
        "S": {
          "type": "object",
          "title": "Sec",
          "properties": {
            "a": {
              "type": "boolean",
              "title": "A"
            },
            "n": {
              "type": "object",
              "title": "Nested",
              "x-group": "Sec",
              "x-showIf": {
                "a": true
              },
              "properties": {
                "b": {
                  "type": "boolean",
                  "title": "B"
                }
              }
            },
            "m": {
              "type": "object",
              "title": "More",
              "x-group": "Elsewhere",
              "properties": {
                "c": {
                  "type": "boolean",
                  "title": "C"
                }
              }
            }
          }
        }
      }
    }, "S");
    compare(groups.map(group => group.title), ["Sec", "Elsewhere"]);
    compare(groups[0].rows.map(row => row.kind), ["field", "group", "field"]);
    compare(groups[0].rows[1].showIf, {
      "a": true
    });
    compare(groups[0].rows[2].groupShowIf, [
      {
        "condition": {
          "a": true
        },
        "path": ["S"]
      }
    ]);
    compare(groups[1].key, "S:Elsewhere");
    compare(groups[1].rows.map(row => row.title), ["More", "C"]);
  }

  // Durations are stored in ms and shown in their unit
  function test_unitScale() {
    compare(SchemaLayout.unitScale("s"), 1000);
    compare(SchemaLayout.unitScale("min"), 60000);
    compare(SchemaLayout.unitScale("d"), 86400000);
    compare(SchemaLayout.unitScale("ms"), 1);
    compare(SchemaLayout.unitScale("px"), 1);
    compare(SchemaLayout.unitScale(""), 1);
  }

  // A condition key may be dotted and climb with `../`
  function test_keyPath() {
    compare(SchemaLayout.keyPath(["A", "b"], "c"), ["A", "b", "c"]);
    compare(SchemaLayout.keyPath(["A", "b"], "open.onHover"), ["A", "b", "open", "onHover"]);
    compare(SchemaLayout.keyPath(["A", "b"], "../c"), ["A", "c"]);
    compare(SchemaLayout.keyPath(["A", "b"], "../../c.d"), ["c", "d"]);
  }

  // `x-card.perField`: the section's description, then a card per direct
  // field by title (with its description, a switch's row labelled
  // "Enabled"), then nested objects
  function test_card_per_field() {
    const groups = SchemaLayout.groups({
      "properties": {
        "S": {
          "type": "object",
          "title": "Sec",
          "description": "About",
          "x-card": {
            "perField": true
          },
          "properties": {
            "z": {
              "type": "boolean",
              "title": "Beta",
              "description": "B"
            },
            "a": {
              "type": "boolean",
              "title": "Alpha",
              "description": "A"
            },
            "g": {
              "type": "string",
              "title": "Gamma"
            },
            "n": {
              "type": "object",
              "title": "Nested",
              "properties": {
                "c": {
                  "type": "boolean",
                  "title": "C"
                }
              }
            }
          }
        }
      }
    }, "S");
    compare(groups.map(group => group.title), ["Sec", "Alpha", "Beta", "Gamma", "Nested"]);
    compare(groups.map(group => group.description), ["About", "A", "B", "", ""]);
    compare(groups.map(group => group.key), ["S", "S:Alpha", "S:Beta", "S:Gamma", "S.n"]);
    compare(groups[1].rows[0].label, "Enabled");
    compare(groups[1].rows[0].title, "Alpha", "still found by its name");
    compare(groups[3].rows[0].label, undefined, "only a switch is relabelled");
    compare(groups[4].rows[0].label, undefined);
  }

  // A hand-built card goes first; with `x-card.folds` it folds, and the
  // real cards that fold take their key as `foldKey` (EntryListCards do)
  function test_card_folds() {
    const groups = SchemaLayout.groups({
      "properties": {
        "S": {
          "type": "object",
          "x-card": {
            "file": "List",
            "folds": true
          },
          "properties": {}
        }
      }
    }, "S");
    compare(groups[0].kind, "card");
    compare(groups[0].key, "S:List");
    verify(groups[0].folds);
    for (const key in schema.properties) {
      const section = schema.properties[key];
      if (section["x-card"]?.folds)
        verify(/^EntryListCard \{|property string foldKey/m.test(files.text("components/views/Settings/" + section["x-card"].file + "Card.qml")), key);
    }
  }

  // `x-card.wide` widens a hand-built card; a field's `x-wide` the
  // generated card it lands on, and only that one
  function test_wide() {
    const groups = SchemaLayout.groups({
      "properties": {
        "S": {
          "type": "object",
          "title": "S",
          "x-card": {
            "file": "List",
            "wide": true
          },
          "properties": {
            "a": {
              "type": "string"
            },
            "b": {
              "type": "array",
              "x-group": "B",
              "x-wide": true,
              "items": {
                "type": "object",
                "properties": {
                  "c": {
                    "type": "string"
                  }
                }
              }
            }
          }
        }
      }
    }, "S");
    compare(groups.map(group => [group.title, group.wide]), [["S", true], ["S", false], ["B", true]]);
  }

  // Wide cards ahead of every narrow one stay first, the rest go last;
  // the category's own card is wide, after its sections'
  function test_categoryGroups_order() {
    const wide = {
      "type": "array",
      "x-wide": true,
      "items": {
        "type": "object",
        "properties": {
          "c": {
            "type": "string"
          }
        }
      }
    };
    const schema = {
      "properties": {
        "S": {
          "type": "object",
          "title": "S",
          "x-card": {
            "file": "Status",
            "wide": true
          },
          "properties": {
            "a": {
              "type": "string",
              "x-group": "A"
            },
            "w": Object.assign({
              "x-group": "W"
            }, wide),
            "b": {
              "type": "string",
              "x-group": "B"
            }
          }
        }
      }
    };
    const groups = SchemaLayout.categoryGroups(schema, {
      "name": "Cat",
      "sections": ["S"],
      "card": "Own",
      "cardTitle": "Own card"
    });
    compare(groups.map(group => group.title), ["S", "A", "B", "W", "Own card"]);
    compare(groups[4].key, "Cat:Own");
    compare(groups.map(group => group.wide), [true, false, false, true, true]);
  }

  // A hand-built card is titled by `x-card.title`, which every real one has
  // (its QML sets none)
  function test_card_titles() {
    const groups = SchemaLayout.groups({
      "properties": {
        "S": {
          "type": "object",
          "title": "Section",
          "x-card": {
            "file": "List",
            "title": "Entries"
          },
          "properties": {}
        }
      }
    }, "S");
    compare(groups[0].title, "Entries");
    for (const key in schema.properties) {
      const section = schema.properties[key];
      if (section["x-card"]?.file)
        verify(typeof section["x-card"].title === "string" && section["x-card"].title !== "", key);
    }
  }

  function test_objectGroups() {
    const groups = SchemaLayout.objectGroups({
      "x-order": ["b", "a"],
      "properties": {
        "a": {
          "x-group": "One"
        },
        "b": {
          "x-group": "Two"
        },
        "c": {},
        "skip": {
          "x-group": "One"
        },
        "hidden": {
          "x-group": "One",
          "x-settings": false
        }
      }
    }, ["skip"]);
    compare(groups.map(g => g.title + ":" + g.keys.join(",")), ["Two:b", "One:a", "Other:c"]);
    compare(Object.keys(groups[1].schema), ["a"]);
    const bar = SchemaLayout.objectGroups(schema.definitions.Bar, ["widgets", "style"]);
    compare(bar.map(g => g.title), ["General", "Size", "Style", "Behaviour"]);
    const style = SchemaLayout.objectGroups(schema.definitions.BarStyle, []);
    compare(style.map(g => g.title), ["Bar widgets", "Bar accents", "Surface shadow"]);
    const menu = SchemaLayout.objectGroups(schema.definitions.EdgeMenu, ["layout.modules"]);
    compare(menu.map(g => g.title), ["General", "Opening", "Placement", "Style", "Closing"]);
  }

  function test_real_schema_intros_exist() {
    for (const key in schema.properties) {
      const intro = schema.properties[key]["x-intro"];
      if (intro)
        verify(files.text("components/views/Settings/" + intro + ".qml").includes("x-intro"), intro);
    }
  }

  // A section whose own `x-showIf` fails (the compositor can't do what it
  // sets) is left out, and its category with it; without `valueOf`, kept
  function test_categories_section_showIf() {
    const field = {
      "type": "string",
      "default": ""
    };
    const schema = {
      "properties": {
        "Hypr": {
          "type": "object",
          "x-category": "Compositor",
          "x-showIf": {
            "/$supports.configModes": true
          },
          "properties": {
            "f": field
          }
        },
        "Look": {
          "type": "object",
          "x-category": "Compositor",
          "properties": {
            "f": field
          }
        }
      }
    };
    const on = SchemaLayout.categories(schema, key => key === "/$supports.configModes");
    compare(on[0].sections, ["Hypr", "Look"]);
    const off = SchemaLayout.categories(schema, key => false);
    compare(off[0].sections, ["Look"]);
    compare(SchemaLayout.categories(schema)[0].sections, ["Hypr", "Look"]);
  }

  // Only the compositor's (`/$`) conditions count, on the section, the
  // objects on the way and the field; the config's are ignored
  function test_compositorAllows() {
    const schema = {
      "properties": {
        "Hypr": {
          "type": "object",
          "x-showIf": {
            "/$supports.configModes": true
          },
          "properties": {
            "f": {
              "type": "string"
            }
          }
        },
        "Look": {
          "type": "object",
          "properties": {
            "inner": {
              "type": "object",
              "properties": {
                "blur": {
                  "type": "boolean",
                  "x-showIf": {
                    "/$supports.blur": true,
                    "opacity": {
                      "not": 100
                    }
                  }
                }
              }
            },
            "plain": {
              "type": "boolean",
              "x-showIf": {
                "gaps": true
              }
            }
          }
        }
      }
    };
    const none = key => false;
    const all = key => true;
    verify(!SchemaLayout.compositorAllows(schema, ["Hypr", "f"], none));
    verify(SchemaLayout.compositorAllows(schema, ["Hypr", "f"], all));
    verify(!SchemaLayout.compositorAllows(schema, ["Look", "inner", "blur"], none));
    verify(SchemaLayout.compositorAllows(schema, ["Look", "inner", "blur"], key => key === "/$supports.blur"));
    verify(SchemaLayout.compositorAllows(schema, ["Look", "plain"], none));
    // Greyed out (x-enabledIf) counts as not settable
    const greyed = {
      "properties": {
        "Look": {
          "properties": {
            "round": {
              "type": "integer",
              "x-enabledIf": {
                "/$supports.windowRounding": true
              }
            }
          }
        }
      }
    };
    verify(!SchemaLayout.compositorAllows(greyed, ["Look", "round"], none));
    verify(SchemaLayout.compositorAllows(greyed, ["Look", "round"], all));
    verify(!SchemaLayout.compositorAllows(schema, ["Look", "missing"], all));
  }

  // `x-categories` orders them and names their icon and page; others
  // follow in schema order; an empty declared one is left out unless it
  // has a page
  function test_categories_order_icon_page() {
    const field = {
      "type": "string",
      "default": ""
    };
    const categories = SchemaLayout.categories({
      "x-categories": [
        {
          "name": "B",
          "icon": "star"
        },
        {
          "name": "Empty"
        },
        {
          "name": "Tools",
          "icon": "build",
          "card": "Tools",
          "cardTitle": "Tool card"
        }
      ],
      "properties": {
        "One": {
          "type": "object",
          "x-category": "A",
          "properties": {
            "f": field
          }
        },
        "Two": {
          "type": "object",
          "x-category": "B",
          "x-links": ["Themes"],
          "properties": {
            "f": field
          }
        },
        "Three": {
          "type": "object",
          "title": "Three",
          "properties": {
            "f": field
          }
        }
      }
    });
    compare(categories.map(c => c.name), ["B", "Tools", "A", "Three"]);
    compare(categories[0].icon, "star");
    compare(categories[0].sections, ["Two"]);
    compare(categories[0].links, ["Themes"]);
    compare([categories[1].card, categories[1].cardTitle], ["Tools", "Tool card"]);
    compare(categories[1].sections, []);
    compare(categories[2].icon, "settings");
    compare(categories[2].card, "");
  }

  function test_real_schema_categories() {
    const categories = SchemaLayout.categories(schema);
    verify(categories.length > 3);
    const declared = schema["x-categories"].map(c => c.name);
    for (const category of categories) {
      verify(declared.includes(category.name), "declared in x-categories: " + category.name);
      if (category.card !== "") {
        verify(files.text("components/views/Settings/" + category.card + "Card.qml").length > 0, category.card);
        continue;
      }
      verify(category.sections.length > 0, category.name);
      for (const key of category.sections)
        verify(SchemaLayout.groups(schema, key).length > 0, key);
    }
    // The bars themselves are the bar editor's; their shared style is here
    verify(!SchemaLayout.groups(schema, "Bars").some(group => group.rows.some(row => row.path[1] === "items")), "Bars.items is edited by the bar editor");
  }

  function test_real_schema_showIf_targets_exist() {
    const bad = [];
    const resolve = node => node?.$ref ? schema.definitions[node.$ref.replace("#/definitions/", "")] : node;
    // `parents`: the objects holding `node`, outermost first, for `../`
    const visit = (node, parents, where) => {
      if (!node || typeof node !== "object" || node.$ref)
        return;
      for (const key in node.properties ?? {}) {
        const prop = node.properties[key];
        const condition = prop["x-showIf"] ?? {};
        const targets = [].concat(Object.keys(condition).filter(target => target !== "anyOf"), ...(condition.anyOf ?? []).map(any => Object.keys(any)));
        for (const target of targets) {
          // The running compositor's, not the config's (SettingsManager.configValueAt)
          if (target.startsWith("/$"))
            continue;
          // The look of the bar a widget sits on (BarsConfig.lookContext): only
          // a bar widget's options have it, and it names a BarStyle field
          if (target.startsWith("$")) {
            if (!/^\w+Widget\.properties$/.test(where) || !target.startsWith("$bar.") || !(target.slice(5) in schema.definitions.BarStyle.properties))
              bad.push(`${where}.${key}: ${target}`);
            continue;
          }
          let found;
          if (target.startsWith("/")) {
            found = target.slice(1).split(".").reduce((s, part) => resolve(s)?.properties?.[part], schema);
          } else {
            // A sibling, dotted into one, or (`../`) the parent's
            let base = node;
            let rest = target;
            let up = parents.length;
            while (rest.startsWith("../")) {
              base = parents[--up];
              rest = rest.slice(3);
            }
            found = rest.split(".").reduce((s, part) => resolve(s)?.properties?.[part], base);
          }
          if (!found)
            bad.push(`${where}.${key}: ${target}`);
        }
        visit(prop, parents.concat([node]), `${where}.${key}`);
        visit(prop.items, [], `${where}.${key}[]`);
      }
    };
    visit(schema, [], "");
    for (const name in schema.definitions)
      visit(schema.definitions[name], [], name);
    compare(bad, []);
  }

  function test_locate() {
    const schema = {
      "x-categories": [
        {
          "name": "Look",
          "icon": "palette"
        }
      ],
      "properties": {
        "Style": {
          "type": "object",
          "title": "Style",
          "x-category": "Look",
          "properties": {
            "size": {
              "type": "integer",
              "title": "Size"
            },
            "shadow": {
              "type": "boolean",
              "title": "Shadow",
              "x-group": "Shadows"
            },
            "font": {
              "type": "object",
              "title": "Font",
              "properties": {
                "family": {
                  "type": "string",
                  "title": "Family"
                }
              }
            }
          }
        },
        "Cards": {
          "type": "object",
          "title": "Cards",
          "x-category": "Look",
          "x-card": {
            "file": "CardList"
          },
          "properties": {
            "on": {
              "type": "boolean",
              "title": "On"
            }
          }
        }
      }
    };
    compare(SchemaLayout.locate(schema, "Style.size"), {
      "category": "Look",
      "key": "Style",
      "title": "Size",
      "row": ["Style", "size"]
    });
    compare(SchemaLayout.locate(schema, ["Style", "shadow"]).key, "Style:Shadows");
    compare(SchemaLayout.locate(schema, "Style.font.family").key, "Style.font");
    // An object: its card, no row
    compare(SchemaLayout.locate(schema, "Style.font"), {
      "category": "Look",
      "key": "Style.font",
      "title": "Font",
      "row": null
    });
    // A section: its first card, the hand-built one when it has one
    compare(SchemaLayout.locate(schema, "Style").key, "Style");
    compare(SchemaLayout.locate(schema, "Cards").key, "Cards:CardList");
    compare(SchemaLayout.locate(schema, "Cards.on").key, "Cards");
    compare(SchemaLayout.locate(schema, "Style.nope"), null);
    compare(SchemaLayout.locate(schema, "Nope"), null);
  }

  // Every `x-link` leads to a setting the settings page shows, or a page
  // the overlay can have; every `x-links` to such a page
  function test_real_schema_links_resolve() {
    const views = schema.definitions.OverlayView.oneOf.map(option => schema.definitions[option.$ref.replace("#/definitions/", "")].properties.type.const);
    const pageOk = link => {
      const parts = link.split(":");
      return (parts[0] === "Layouts" || views.includes(parts[0])) && (parts.length === 1 || (parts[0] === "Layouts" && ["lockscreen", "greeter", "desktop"].includes(parts[1])));
    };
    const bad = [];
    const visit = (node, where) => {
      if (!node || typeof node !== "object")
        return;
      for (const link of [].concat(node["x-link"] ?? [])) {
        if (link.setting !== undefined ? SchemaLayout.locate(schema, link.setting) === null : !pageOk(link.page ?? ""))
          bad.push(`${where}: ${JSON.stringify(link)}`);
      }
      for (const link of node["x-links"] ?? [])
        if (!pageOk(link))
          bad.push(`${where}: x-links ${link}`);
      for (const key in node)
        if (key !== "x-link" && typeof node[key] === "object")
          visit(node[key], `${where}.${key}`);
    };
    visit(schema, "");
    compare(bad, []);
  }

  // The bar editor's links to the shared bar style (BarsPanel's style
  // groups, WidgetInspector) find their cards
  function test_bar_style_links_resolve() {
    const targets = ["Bars.style"].concat(SchemaLayout.objectGroups(schema.definitions.BarStyle, []).map(group => "Bars.style." + group.keys[0]));
    compare(targets.filter(target => SchemaLayout.locate(schema, target) === null), []);
    compare(targets.length > 1, true);
  }
}
