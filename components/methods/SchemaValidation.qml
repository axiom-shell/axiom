pragma Singleton
import QtQuick

/**
 * JSON-schema helpers for the config: filling in defaults (for new entries
 * and previews; pruning, loading and validating saves are the axiom
 * binary's), and validation, which only the shared fixtures still use as
 * the binary's reference (tests/Shared.qml). Every entry point takes the root schema, which is
 * used to resolve `#/definitions/...` refs, so this has no dependency on
 * ConfigManager (which lets ConfigManager load eagerly at startup).
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

  // Every reason `value` fails `schema` (empty when it's valid)
  function validationErrors(value, schema, path = '') {
    _ctx.root = schema;
    const errors = [];
    _validate(value, schema, path, errors);
    return errors;
  }

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

  function _validate(value, schema, path, errors) {
    if (!schema)
      return;

    schema = _resolve(schema);
    // An inheriting setting is null while it takes its value from elsewhere
    if (value === null && schema["x-inherit"])
      return;

    if (schema.type) {
      if (!_validateType(value, schema.type, path, errors)) {
        return;
      }
    }

    if (schema.oneOf) {
      _validateOneOf(value, schema.oneOf, path, errors);
      return;
    }

    if (schema.enum && !schema.enum.includes(value)) {
      errors.push(`${path}: value "${value}" not in allowed values [${schema.enum.join(', ')}]`);
    }

    if (schema.minimum !== undefined && value < schema.minimum) {
      errors.push(`${path}: value ${value} is less than minimum ${schema.minimum}`);
    }
    if (schema.maximum !== undefined && value > schema.maximum) {
      errors.push(`${path}: value ${value} is greater than maximum ${schema.maximum}`);
    }

    if (schema.exclusiveMinimum !== undefined && value <= schema.exclusiveMinimum) {
      errors.push(`${path}: value ${value} must be greater than ${schema.exclusiveMinimum}`);
    }
    if (schema.exclusiveMaximum !== undefined && value >= schema.exclusiveMaximum) {
      errors.push(`${path}: value ${value} must be less than ${schema.exclusiveMaximum}`);
    }

    if (schema.pattern && typeof value === 'string') {
      const regex = new RegExp(schema.pattern);
      if (!regex.test(value)) {
        errors.push(`${path}: value "${value}" does not match pattern ${schema.pattern}`);
      }
    }

    if (schema.type === 'object' && typeof value === 'object' && value !== null) {
      _validateObject(value, schema, path, errors);
    }

    if (schema.type === 'array' && Array.isArray(value)) {
      _validateArray(value, schema, path, errors);
    }
  }

  function _validateType(value, expectedType, path, errors) {
    const actualType = Array.isArray(value) ? 'array' : value === null ? 'null' : typeof value;

    if (expectedType === 'integer') {
      if (!Number.isInteger(value)) {
        errors.push(`${path}: expected integer, got ${typeof value}`);
        return false;
      }
    } else if (expectedType === 'array') {
      if (!Array.isArray(value)) {
        errors.push(`${path}: expected array, got ${actualType}`);
        return false;
      }
    } else if (expectedType === 'object') {
      if (typeof value !== 'object' || value === null || Array.isArray(value)) {
        errors.push(`${path}: expected object, got ${actualType}`);
        return false;
      }
    } else if (actualType !== expectedType) {
      errors.push(`${path}: expected ${expectedType}, got ${actualType}`);
      return false;
    }

    return true;
  }

  function _validateObject(value, schema, path, errors) {
    if (schema.required) {
      schema.required.forEach(requiredProp => {
        if (!(requiredProp in value)) {
          errors.push(`${path ? path + '.' : ''}${requiredProp}: required field missing`);
        }
      });
    }

    if (schema.properties) {
      Object.keys(value).forEach(key => {
        const propSchema = schema.properties[key];
        if (propSchema) {
          const propPath = path ? `${path}.${key}` : key;
          _validate(value[key], propSchema, propPath, errors);
        }
      });
    }

    if (schema.additionalProperties !== undefined) {
      const definedProps = Object.keys(schema.properties || {});
      Object.keys(value).forEach(key => {
        if (!definedProps.includes(key)) {
          if (schema.additionalProperties === false) {
            errors.push(`${path}.${key}: additional property not allowed`);
          } else if (typeof schema.additionalProperties === 'object') {
            const propPath = path ? `${path}.${key}` : key;
            _validate(value[key], schema.additionalProperties, propPath, errors);
          }
        }
      });
    }

    if (schema.patternProperties) {
      Object.keys(value).forEach(key => {
        Object.entries(schema.patternProperties).forEach(([pattern, propSchema]) => {
          const regex = new RegExp(pattern);
          if (regex.test(key)) {
            const propPath = path ? `${path}.${key}` : key;
            _validate(value[key], propSchema, propPath, errors);
          }
        });
      });
    }
  }

  function _validateArray(value, schema, path, errors) {
    if (schema.items) {
      value.forEach((item, index) => {
        const itemPath = `${path}[${index}]`;
        _validate(item, schema.items, itemPath, errors);
      });
    }

    if (schema.minItems !== undefined && value.length < schema.minItems) {
      errors.push(`${path}: array has ${value.length} items, minimum is ${schema.minItems}`);
    }
    if (schema.maxItems !== undefined && value.length > schema.maxItems) {
      errors.push(`${path}: array has ${value.length} items, maximum is ${schema.maxItems}`);
    }
  }

  function _validateOneOf(value, oneOfSchemas, path, errors) {
    const matchingSchemas = [];
    // Errors from options whose `type` const matched, so a discriminated
    // union reports why the right option failed instead of just "no match"
    const typedErrors = [];

    for (let i = 0; i < oneOfSchemas.length; i++) {
      const subErrors = [];
      const subSchema = oneOfSchemas[i];

      const resolvedSchema = _resolve(subSchema);

      if (resolvedSchema.properties?.type?.const !== undefined) {
        if (value?.type !== resolvedSchema.properties.type.const) {
          continue;
        }
      }

      _validate(value, resolvedSchema, path, subErrors);

      if (subErrors.length === 0) {
        matchingSchemas.push(i);
      } else if (resolvedSchema.properties?.type?.const !== undefined) {
        typedErrors.push(...subErrors);
      }
    }

    if (matchingSchemas.length === 0) {
      if (typedErrors.length > 0)
        errors.push(...typedErrors);
      else
        errors.push(`${path}: value does not match any schema in oneOf`);
    } else if (matchingSchemas.length > 1) {
      errors.push(`${path}: value matches multiple schemas in oneOf (indices: ${matchingSchemas.join(', ')})`);
    }
  }
}
