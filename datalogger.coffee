module.exports = (env) ->

  convict = env.require "convict"
  Q = env.require 'q'
  assert = env.require 'cassert'
  _ = env.require 'lodash'
  fs = env.require 'fs.extra'

  path = require 'path'

  class DataLoggerPlugin extends env.plugins.Plugin

    deviceListener: {}

    init: (@app, @framework, @config) =>
      conf = convict require("./datalogger-config-shema")
      conf.load config 
      conf.validate()

      unless @config.devices? then @config.devices = []

      @framework.on "device", (device) =>
        c =  @getDeviceConfig device.id
        if c? then @addLoggerForDevice device, c.attributes
        return

      @framework.on "after init", =>
        
        mobileFrontend = @framework.getPlugin 'mobile-frontend'
        if mobileFrontend?
          mobileFrontend.registerAssetFile 'js', "pimatic-datalogger/app/js/highstock.js"
          mobileFrontend.registerAssetFile 'js', "pimatic-datalogger/app/datalogger-page.coffee"
          mobileFrontend.registerAssetFile 'css', "pimatic-datalogger/app/css/datalogger.css"
          mobileFrontend.registerAssetFile 'html', "pimatic-datalogger/app/datalogger-page.jade"
        else
          env.logger.warn "datalogger could not find mobile-frontend. No gui will be available"

        for sensor in @config.devices 
          unless @deviceListener[sensor.id]?
            env.logger.warn "No device with id: #{sensor.id} found to log values."
        return

      sendError = (res, error) =>
        res.send 406, success: false, message: error.message

      sendSuccess = (res, message) =>
        res.send success: true, message: message

      getDeviceFromRequest = (req) =>
        deviceId = req.params.deviceId
        if not deviceId? or deviceId is "undefined"
          throw new Error "No deviceId given" 
        device = @framework.getDeviceById deviceId
        unless device?
          throw new Error "Could not find device."
        return device

      getAttributeFromRequest = (req, device) =>
        attribute = req.params.attribute
        if not attribute? or attribute is "undefined"
          throw new Error "No attribute name given." 
        unless device.hasAttribute attribute
          throw new Error "Illegal value for this device."
        return attribute

      @app.get '/datalogger/info/:deviceId', (req, res, next) =>
        try
          device = getDeviceFromRequest req
        catch e
          return sendError res, e

        c = @getDeviceConfig device.id
        loggedAttributes = (if c? then c.attributes else [])

        info =
         loggingAttributes: {}

        for attribute of device.attributes
          info.loggingAttributes[attribute] = (attribute in loggedAttributes)

        res.send info

      @app.get '/datalogger/add/:deviceId/:attribute', (req, res, next) =>
        try
          device = getDeviceFromRequest req
          attribute = getAttributeFromRequest req, device
        catch e
          return sendError res, e

        @addDeviceToConfig device.id, [attribute]
        @addLoggerForDevice device, [attribute]
        sendSuccess res, "Added logging for #{attribute}."

      @app.get '/datalogger/remove/:deviceId/:attribute', (req, res, next) =>
        try
          device = getDeviceFromRequest req
          attribute = getAttributeFromRequest req, device
        catch e
          return sendError res, e

        @removeDeviceFromConfig device.id, [attribute]
        @removeLoggerForDevice device, [attribute]
        sendSuccess res, "Removed logging for #{attribute}."

      @app.get '/datalogger/data/:deviceId/:attribute', (req, res, next) =>
        try
          device = getDeviceFromRequest req
          attribute = getAttributeFromRequest req, device
        catch e
          console.log e
          return sendError res, e

        @getData(device.id, attribute).then( (data) =>
          res.send
            title: 
              text: "#{device.name}: #{attribute}"
            tooltip:
              valueDecimals: 2
            yAxis:
              labels:
                format: "{value}"
            series: [
              name: "Messwert"
              data: data
            ]
        ).done()

    logData: (deviceId, attribute, value, date = new Date()) ->
      assert deviceId?
      assert attribute?
      assert value?

      file = @getPathOfLogFile deviceId, attribute, date
      defer = Q.defer()
      Q.nfcall(fs.exists, file, defer.resolve)
      defer.promise.then( (exists) =>
        unless exists
          Q.nfcall fs.mkdirs, path.dirname(file)
      ).then( =>
        Q.nfcall fs.appendFile, file, "#{date.getTime()},#{value}\n"
      )



    getData: (deviceId, attribute, date = new Date()) ->
      file = @getPathOfLogFile deviceId, attribute, date
      defer = Q.defer()
      Q.nfcall(fs.exists, file, defer.resolve)
      defer.promise.then( (exists) =>
        unless exists then return []
        else Q.nfcall(fs.readFile, file).then( (csv) =>
          csv = csv.toString()
          if csv.length is 0 then return []
          json = '[[' + 
            csv.replace(/\r\n|\n|\r/gm, '],[') #replace new lines with `],[`
            .replace(/,\[\]/g, '') # remove empty arrays: `[]`
            .replace(/\],\[$/, '') + # remove last `],[`
            ']]'
          JSON.parse(json)
        )
      )

    getPathOfLogFile: (deviceId, attribute, date) ->
      assert deviceId?
      assert attribute?
      assert date instanceof Date
      pad = (n) => if n < 10 then '0'+n else n
      year = pad date.getFullYear()
      month = pad(date.getMonth()+1)
      day = pad date.getDate()
      return path.resolve @framework.maindir, 
        "../../datalogger/#{deviceId}/#{attribute}/#{year}/#{month}/#{day}.csv"


    # ##addLoggerForDevice()
    # Add a sensor value listener for the given device and attributes
    addLoggerForDevice: (device, attributes) ->
      assert device? and device.id?
      assert Array.isArray attributes

      for attribute in attributes
        do (attribute) =>
          listener = (value) => @logData(device.id, attribute, value).done()
          unless @deviceListener[device.id]?
            @deviceListener[device.id] =
              listener: {}
          unless @deviceListener[device.id].listener[attribute]?
            @deviceListener[device.id].listener[attribute] = listener  
            device.on attribute, listener
      return

    removeLoggerForDevice: (device, attributes) ->
      if @deviceListener[device.id]?
        for attribute in attributes
          do (attribute) =>
            listener = @deviceListener[device.id].listener[attribute]
            device.removeListener attribute, listener
            delete @deviceListener[device.id].listener[attribute]
        if (l for l of @deviceListener[device.id].listener).length is 0
          delete @deviceListener[device.id]
      return

    # ##getDeviceConfig()
    # Get the config entry for the given if
    getDeviceConfig: (deviceId) ->
      assert deviceId?
      return _(@config.devices).find (s) => s.id is deviceId

    # ##addDeviceToConfig()
    # Add the given device id with the fiven sensor values to the config.
    addDeviceToConfig: (deviceId, attributes) ->
      assert deviceId?
      assert Array.isArray attributes
      # Get the config entry for the given id.
      entry = @getDeviceConfig deviceId
      # If the entry does not exist
      unless entry?
        # then create it.
        @config.devices.push
          id: deviceId
          attributes: attributes
      else 
        # Else just add the sensor values.
        entry.attributes = _.union entry.attributes, attributes
      # Save the config and return.
      @framework.saveConfig()
      return

    # ##removeDeviceFromConfig()
    # Removes the given sensor values from the sensor config entry with the id of deviceId
    removeDeviceFromConfig: (deviceId, attributesToRemove) ->
      assert deviceId?
      assert Array.isArray attributesToRemove
      # Get the sensor config entry.
      entry = @getDeviceConfig deviceId
      # If an entry was found
      if entry?
        # then remove the given sensor values.
        entry.attributes = _.difference entry.attributes, attributesToRemove
        # If the entry has no sensor values anymore
        if entry.attributes.length is 0
          # then remove the entry completly from the config.
          @config.devices = _.filter @config.devices, (s) => s.id isnt deviceId
      # Save the config and return.
      @framework.saveConfig()
      return

  return new DataLoggerPlugin

