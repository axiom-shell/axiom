pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// itemDelegate for an array-of-objects SchemaField: the item's fields,
// generated from the array's `items` schema. itemData/itemIndex are
// assigned imperatively by SchemaObjectArray's Loader after construction,
// so they must NOT be `required`.
SchemaPropertiesForm {
  id: root

  required property var itemSchema
  property var itemData: null
  property int itemIndex: -1

  signal itemEdited(int index, string key, var value)

  propertiesSchema: root.itemSchema.properties ?? ({})
  order: root.itemSchema["x-order"] ?? []
  values: root.itemData ?? ({})
  onEdited: (path, value) => root.itemEdited(root.itemIndex, path[0], value)

  Layout.fillWidth: true
}
