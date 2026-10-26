pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.services.core
import qs.services.apps

// The launcher's /config entry: its completion rows (`options`) for
// settings, saving and restoring the config, examples and community
// setups, and what picking one does (`run`). Not a singleton:
// LauncherCommands holds one for its `config` entry.
QtObject {
  id: root

  // Every row's title is the whole argument it stands for, since rows are
  // matched against the typed argument and Tab completes to the title
  function options(arg) {
    const space = arg.indexOf(" ");
    if (space < 0) {
      const rows = [
        {
          title: "save",
          subtitle: SavedConfigsManager.modified ? I18n.tr("Save changes to \"{0}\"", SavedConfigsManager.active) : I18n.tr("Save the current config under a name"),
          glyph: "save",
          value: {
            next: "save "
          }
        },
        {
          title: "restore",
          subtitle: I18n.tr("Restore a saved config"),
          glyph: "settings_backup_restore",
          value: {
            next: "restore "
          }
        },
        {
          title: "example",
          subtitle: I18n.tr("Apply an example setup (the current config is saved first)"),
          glyph: "auto_awesome_mosaic",
          value: {
            next: "example "
          }
        }
      ].concat(CommunitySetupsManager.enabled ? [
        {
          title: "community",
          subtitle: I18n.tr("Search the community setups and apply one (the current config is saved first)"),
          glyph: "groups",
          value: {
            next: "community "
          }
        }
      ] : []);
      return rows.concat(SettingsManager.settingPaths.map(entry => ({
            title: entry.key,
            subtitle: I18n.tr(entry.schema.title ?? entry.key) + " · " + root._show(SettingsManager.valueOf(entry.key), entry.schema),
            value: {
              next: entry.key + " "
            }
          })));
    }

    const head = arg.slice(0, space);
    const rest = arg.slice(space + 1);
    const names = root._savedConfigNames();
    // Only the active saved config is offered to overwrite; another is
    // replaced only when its name is typed in full, as on the settings page
    const active = SavedConfigsManager.active;
    if (head === "save") {
      const name = SavedConfigsManager.sanitize(rest);
      const rows = name === "" || name === active ? [] : [
        {
          title: "save " + rest.trim(),
          subtitle: names.includes(name) ? I18n.tr("Replace \"{0}\"", name) : I18n.tr("Save as \"{0}\"", name),
          value: {
            save: name
          }
        }
      ];
      return active === "" ? rows : rows.concat([
        {
          title: "save " + active,
          subtitle: SavedConfigsManager.modified ? I18n.tr("Save changes to the current config") : I18n.tr("No changes since saved"),
          value: {
            save: active
          }
        }
      ]);
    }
    if (head === "restore")
      return names.filter(saved => saved === active).concat(names.filter(saved => saved !== active)).map(saved => ({
            title: "restore " + saved,
            subtitle: saved !== active ? "" : SavedConfigsManager.modified ? I18n.tr("Current · discards unsaved changes") : I18n.tr("Current"),
            value: {
              restore: saved
            }
          }));

    if (head === "example")
      return SavedConfigsManager.examples.map(example => ({
            title: "example " + example.name,
            subtitle: example.description,
            value: {
              example: example.name
            }
          }));

    if (head === "community" && CommunitySetupsManager.enabled)
      return root._communityOptions(rest);

    const entry = SettingsManager.settingFor(head);
    if (!entry)
      return [
        {
          title: arg.trim(),
          subtitle: I18n.tr("No setting \"{0}\"", head),
          glyph: "warning",
          value: {}
        }
      ];
    const schema = entry.schema;
    const current = SettingsManager.valueOf(entry.key);
    const choices = schema.type === "boolean" ? ["on", "off"] : schema.type === "string" ? SettingsManager.optionsFor(schema) : null;
    const setRow = (text, parsed) => ({
          title: entry.key + " " + text,
          subtitle: parsed.error ?? (JSON.stringify(parsed.value) === JSON.stringify(current) ? I18n.tr("Current") : I18n.tr("Set {0} to {1} (now {2})", I18n.tr(schema.title ?? entry.key), root._show(parsed.value, schema), root._show(current, schema))),
          glyph: parsed.error ? "warning" : "",
          value: parsed.error ? {} : {
            key: entry.key,
            set: parsed.value
          }
        });
    // Last, so Enter still sets the first value; only while a card shows it
    const showRows = SettingsManager.locate(entry.key) ? [
      {
        title: I18n.tr("Show in settings"),
        subtitle: I18n.tr("Open the settings page on {0}", I18n.tr(schema.title ?? entry.key)),
        glyph: "settings",
        value: {
          show: entry.key
        }
      }
    ] : [];
    const typed = rest.trim();
    if (typed === "" && !choices)
      return [
        {
          title: entry.key,
          subtitle: I18n.tr("Type a value (now {0})", root._show(current, schema)),
          value: {
            next: entry.key + " "
          }
        }
      ].concat(showRows);
    let rows = [];
    // Typed text that isn't (the start of) a choice gets a row of its own,
    // so free values, and why one is rejected, show
    if (typed !== "" && !(choices ?? []).some(choice => choice.toLowerCase().startsWith(typed.toLowerCase())))
      rows.push(setRow(typed, SettingsManager.parseValue(schema, rest)));
    if (choices)
      rows = rows.concat(choices.map(choice => {
        const text = choice === "" ? "\"\"" : choice;
        return setRow(text, SettingsManager.parseValue(schema, text));
      }));
    return rows.concat(showRows);
  }

  function run(value) {
    if (value?.next)
      return "/config " + value.next;
    if (value?.save) {
      SavedConfigsManager.save(value.save);
      return;
    }
    if (value?.restore) {
      SavedConfigsManager.restore(value.restore);
      return;
    }
    if (value?.example) {
      SavedConfigsManager.applyExample(value.example);
      return;
    }
    if (value?.community) {
      CommunitySetupsManager.apply(value.community, false);
      return;
    }
    // After the launcher has closed, so the overlay gets the keyboard
    if (value?.show) {
      Qt.callLater(() => SettingsManager.openSetting(value.show));
      return;
    }
    if (value?.key !== undefined && !SettingsManager.commitValue(value.key, value.set))
      console.warn("[LauncherConfigBrowser] Could not set", value.key);
    return false;
  }

  // The community setups matching `rest` (CommunityCatalog.search, so
  // `matched`), with their thumbnails; the catalog is downloaded the first
  // time they're asked for
  function _communityOptions(rest) {
    CommunitySetupsManager.open();
    if (!CommunitySetupsManager.loaded)
      return [
        {
          title: "community " + rest,
          subtitle: CommunitySetupsManager.loading ? I18n.tr("Loading the community setups…") : CommunitySetupsManager.status || I18n.tr("No community setups yet"),
          glyph: CommunitySetupsManager.loading ? "hourglass_empty" : "cloud_off",
          value: {}
        }
      ];
    return CommunitySetupsManager.search(rest, []).map(setup => ({
          title: "community " + setup.id,
          subtitle: setup.compatible ? I18n.tr("{0} by {1} · {2}", setup.title, setup.author, setup.description) : I18n.tr("{0} needs a newer axiom", setup.title),
          glyph: setup.compatible ? "" : "warning",
          image: CommunitySetupsManager.thumbs[setup.id] ?? "",
          matched: true,
          value: setup.compatible ? {
            community: setup.id
          } : {}
        }));
  }

  function _show(value, schema) {
    if (schema.type === "boolean")
      return value ? I18n.tr("On") : I18n.tr("Off");
    if (Array.isArray(value))
      return value.length > 0 ? value.join(", ") : I18n.tr("None");
    if (value === "")
      return I18n.tr("Empty");
    return String(value);
  }

  function _savedConfigNames() {
    const names = [];
    const model = SavedConfigsManager.model;
    for (let i = 0; i < model.count; i++)
      names.push(model.get(i, "fileBaseName"));
    return names;
  }
}
