module.exports = (env) ->

  class DataLoggerPlugin extends env.plugins.Plugin


    init: (@app, @framework, @config) =>
      env.logger.warn """
        The pimatic-datalogger plugin is deprecated, because pimatic >= 0.8.0 has build in support
        for logging to databases. Please remove the plugin from your config.
      """

  return new DataLoggerPlugin

