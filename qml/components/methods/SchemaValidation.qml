pragma Singleton
import QtQuick

/**
 * JSON-schema helpers for the config: filling in defaults (for new entries
 * and previews) and resolving a $ref; pruning, loading and validating are
 * the axiom binary's (internal/config), which the shared fixtures check
 * these against (tests/Shared.qml). Every entry point takes the root
 * schema, which is used to resolve `#/definitions/...` refs, so this has
 * no dependency on ConfigManager (which lets ConfigManager load eagerly at
 * startup).
 */
QtObject {
  id: root

  // Root schema of the call in progress, for $ref resolution. Held in a
  // plain JS object (mutated, never reassigned) so setting it doesn't emit
  // a property change: callers evaluate these functions inside bindings
  // (e.g. ConfigManager's eager load), and a notifying write here would
  // re-trigger those bindings in a loop.
  readonly property var _ctx: ({
      root: {}
    })

  /**
   * Returns a deep copy of `value` with every missing key that has a schema
   * `default` filled in, recursing into objects and array items. Objects
   * with declared properties are created when missing, so nested defaults
   * always resolve. A oneOf whose options are told apart by a `type`
   * const (bar widgets) uses the option matching the value's `type`; any
   * other oneOf is left untouched.
   */
  function applyDefaults(value, schema, root = schema) {
    _ctx.root = root;
    const copy = value === undefined ? undefined : JSON.parse(JSON.stringify(value));
    return _applyDefaults(copy, schema);
  }

  // `schema` with its $ref resolved, for walking a value along its schema
  function resolveRef(schema, root) {
    _ctx.root = root;
    return _resolve(schema);
  }

  // A $ref's definition, with any keys beside the $ref (a `default`,
  // `title`, …) over it, so one definition can serve with different
  // defaults (Lockscreen.layout and Greeter.layout share ScreenLayout)
  function _resolve(schema) {
    if (schema && schema.$ref) {
      const refPath = schema.$ref.replace('#/definitions/', '');
      const definition = _ctx.root?.definitions?.[refPath];
      if (!definition)
        return schema;
      const extra = Object.keys(schema).filter(key => key !== '$ref');
      if (extra.length === 0)
        return definition;
      const merged = Object.assign({}, definition);
      extra.forEach(key => merged[key] = schema[key]);
      return merged;
    }
    return schema;
  }

  // The oneOf option whose `type` const matches value.type, or null
  function _discriminate(value, schema) {
    if (!_isPlainObject(value))
      return null;
    for (const option of schema.oneOf) {
      const resolved = _resolve(option);
      if (resolved?.properties?.type?.const !== undefined && resolved.properties.type.const === value.type)
        return resolved;
    }
    return null;
  }

  function _isPlainObject(value) {
    return typeof value === 'object' && value !== null && !Array.isArray(value);
  }

  function _applyDefaults(value, schema) {
    schema = _resolve(schema);
    if (schema?.oneOf)
      schema = _discriminate(value, schema);
    if (!schema)
      return value;

    if (value === undefined && schema.default !== undefined)
      value = JSON.parse(JSON.stringify(schema.default));

    if (schema.type === 'object' && schema.properties) {
      if (value === undefined)
        value = {};
      if (_isPlainObject(value)) {
        for (const key in schema.properties) {
          const filled = _applyDefaults(value[key], schema.properties[key]);
          if (filled !== undefined)
            value[key] = filled;
        }
      }
    }

    if (schema.type === 'array' && Array.isArray(value) && schema.items) {
      for (let i = 0; i < value.length; i++)
        value[i] = _applyDefaults(value[i], schema.items);
    }

    return value;
  }
}
