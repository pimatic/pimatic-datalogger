# #datalogger configuration options

# Defines a `node-convict` config-schema and exports it.
module.exports = {
  type: "string"
  properties:
    sensors:
      description: "The sensors to log"
      type: "array"
      default: []
}
