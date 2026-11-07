pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.services.compositor

/*
 * The one prompt for requests the system starts or that come with no
 * menu open (polkit, Bluetooth pairing, VPN secrets, a Wi-Fi password, a
 * drive's passphrase): a queue showing one request at a time, drawn by
 * PromptWindow (shell/Prompt) on the monitor focused when it came to the
 * front, so two requests never fight over the screen. A Wi-Fi password or
 * drive passphrase asked from its menu stays in its row instead.
 *
 * A source calls request(spec, onAnswer, onCancel) and keeps the id:
 *   spec: { icon (a glyph), title, message, code (shown large: a
 *   PIN or passkey), entered (how many of code's digits are typed, -1
 *   none), fields [{ key, label, secret, digits, maxLength }], actions
 *   [{ id, label, primary }], error, waits, outsideCancels, content,
 *   marks (a ShellManager.onScreen kind the card marks as the primary
 *   action runs: what it leads to is the user's doing) }
 * An action's button calls onAnswer(actionId, values) (values by field
 * key); Escape, and a click outside the card unless outsideCancels is
 * false, call onCancel(). Answered, the request goes, unless it waits:
 * then it stays, busy, until the source update()s it (an error: asked
 * again) or withdraw()s it. update(id, changes) changes a shown request
 * (the code as a keyboard types, an error); withdraw(id) removes one its
 * source ended, calling neither. content "polkit" draws PolkitManager's
 * card instead of the fields and actions.
 *
 * Nothing is polled; nothing survives a reload (the sources ask again).
 */
QtObject {
  id: root

  // The request shown, else null (spec's keys filled in, plus id, busy
  // and attempt: how many times an error came back)
  readonly property var current: _queue.length > 0 ? _queue[0] : null
  // The monitor the shown request is on: the focused one when it came to
  // the front
  readonly property string screenName: _screenName

  // Queues a request; returns its id
  function request(spec, onAnswer, onCancel) {
    const id = "prompt-" + (++root._seq);
    const s = spec ?? {};
    const entry = {
      "id": id,
      "icon": s.icon ?? "",
      "title": s.title ?? "",
      "message": s.message ?? "",
      "code": s.code ?? "",
      "entered": s.entered ?? -1,
      "fields": (s.fields ?? []).map(f => Object.assign({
          "label": "",
          "secret": true,
          "digits": false,
          "maxLength": 0
        }, f)),
      "actions": s.actions ?? [],
      "error": s.error ?? "",
      "waits": s.waits ?? false,
      "outsideCancels": s.outsideCancels ?? true,
      "content": s.content ?? "",
      "marks": s.marks ?? "",
      "busy": false,
      "attempt": 0
    };
    root._handlers[id] = {
      "answer": onAnswer ?? null,
      "cancel": onCancel ?? null
    };
    root._queue = root._queue.concat([entry]);
    return id;
  }

  // The usual buttons: Cancel (id "cancel"), then the primary action
  function cancelOr(id, label) {
    return [
      {
        "id": "cancel",
        "label": I18n.tr("Cancel")
      },
      {
        "id": id,
        "label": label,
        "primary": true
      }
    ];
  }

  // Changes a queued request's spec keys; an error set clears busy and
  // counts an attempt (the card clears its fields and shakes)
  function update(id, changes) {
    root._queue = root._queue.map(entry => {
      if (entry.id !== id)
        return entry;
      const next = Object.assign({}, entry, changes ?? {});
      if ((changes ?? {}).error !== undefined) {
        next.busy = false;
        if (next.error !== "")
          next.attempt = entry.attempt + 1;
      }
      return next;
    });
  }

  // Removes a request its source ended, calling neither callback
  function withdraw(id) {
    root._remove(id);
  }

  // The card's action: onAnswer(actionId, values); the request goes, or
  // waits busy for its source
  function answer(id, actionId, values) {
    const entry = root._queue.find(e => e.id === id);
    if (!entry || entry.busy)
      return;
    const handler = root._handlers[id]?.answer ?? null;
    if (entry.waits)
      root._queue = root._queue.map(e => e.id === id ? Object.assign({}, e, {
          "busy": true
        }) : e);
    else
      root._remove(id);
    if (handler)
      handler(actionId, values ?? {});
  }

  // Escape or a click outside: the request goes, onCancel()
  function cancel(id) {
    if (!root._queue.some(e => e.id === id))
      return;
    const handler = root._handlers[id]?.cancel ?? null;
    root._remove(id);
    if (handler)
      handler();
  }

  property var _queue: []
  // id -> { answer, cancel }
  property var _handlers: ({})
  property int _seq: 0
  property string _screenName: ""
  property string _frontId: ""

  function _remove(id) {
    root._queue = root._queue.filter(e => e.id !== id);
    delete root._handlers[id];
  }

  onCurrentChanged: {
    const id = root.current?.id ?? "";
    if (id !== "" && id !== root._frontId)
      root._screenName = CompositorManager.focusedOutput || General.primaryMonitor;
    root._frontId = id;
  }
}
