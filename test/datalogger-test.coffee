module.exports = (env) ->

  assert = env.require "assert"
  express = env.require 'express'
  request = env.require 'supertest'

  fs = env.require 'fs.extra'
  os = require 'os'
  events = require 'events'
  path = require 'path'

  describe "datalogger", ->

    plugin = (require '../datalogger') env

    before =>
      @app = express()
      @frameworkDummy = new events.EventEmitter
      @frameworkDummy.maindir = "#{os.tmpdir()}/pimatic-test/mode_modules/pimatic"
      @config = {}
      fs.mkdirsSync @frameworkDummy.maindir
      @dataloggerDir = "#{os.tmpdir()}/pimatic-test/datalogger"

      @testDevice = new env.devices.Sensor
      @testDevice.id = "test1"
      @testDevice.name = "test 1"
      @testDevice.properties =
        t1: {}
        t2: {}



    after =>
      fs.rmrfSync @frameworkDummy.maindir

    describe '#init', =>

      it 'should init', =>
        plugin.init @app, @frameworkDummy, @config

        assert @config.sensors
        assert Array.isArray @config.sensors

    describe 'getDeviceConfig()', =>

      it 'should get the entry', =>
        @config.sensors = [
          {
            id: "test"
            properties: ["t1", "t2"]
          }
        ]

        entry = plugin.getDeviceConfig("test")
        assert entry?
        assert.deepEqual entry, @config.sensors[0]

      it 'should not find the entry', =>
        @config.sensors = [
          {
            id: "test"
            properties: ["t1", "t2"]
          }
        ]

        entry = plugin.getDeviceConfig "test2"
        assert not entry?


    describe 'addDeviceToConfig()', =>
      saveConfigCalled = false

      beforeEach =>
        saveConfigCalled = false
        @frameworkDummy.saveConfig = =>
          saveConfigCalled = true

      it 'should add the first entry', =>
        
        @config.sensors = []
        expectedEntry = 
          id: "test"
          properties: ["t1", "t2"]

        plugin.addDeviceToConfig "test", ["t1", "t2"]
        assert.deepEqual expectedEntry, @config.sensors[0]
        assert saveConfigCalled

      it 'should add the sensor value', =>

        expectedEntry = 
          id: "test"
          properties: ["t1", "t2", "t3"]

        plugin.addDeviceToConfig "test", ["t3"]
       
        assert.deepEqual expectedEntry, @config.sensors[0]
        assert saveConfigCalled

      it 'should add the second sensor', =>

        expectedEntry = 
          id: "test2"
          properties: ["t3"]

        plugin.addDeviceToConfig "test2", ["t3"]
       
        assert.equal 2, @config.sensors.length
        assert.deepEqual expectedEntry, @config.sensors[1]
        assert saveConfigCalled

    describe 'removeDeviceFromConfig()', =>
      
      saveConfigCalled = false
      beforeEach =>
        saveConfigCalled = false
        @frameworkDummy.saveConfig = =>
          saveConfigCalled = true

      it 'should remove the entry', =>

        @config.sensors = [
          {
            id: "test"
            properties: ["t1", "t2"]
          }
        ]

        plugin.removeDeviceFromConfig "test", ["t1", "t2"]
        assert.equal 0, @config.sensors.length
        assert saveConfigCalled

      it 'should remove a sensorValue', =>

        @config.sensors = [
          {
            id: "test"
            properties: ["t1", "t2"]
          }
        ]

        expectedEntry = 
          id: "test"
          properties: ["t1"]


        plugin.removeDeviceFromConfig "test", ["t2"]
        assert.equal 1, @config.sensors.length
        assert.deepEqual expectedEntry, @config.sensors[0]
        assert saveConfigCalled

    describe 'getPathOfLogFile()', =>

      it 'should return the right path', =>
        file = plugin.getPathOfLogFile 'test', 't1', new Date(2013, 1, 1, 7, 0, 0)
        assert.equal file, "#{@dataloggerDir}/test/t1/2013/02/01.csv"


    describe 'getData()', =>

      it 'should return a empty array', (finish) =>
        deviceId = 'test'
        propertyName = 't1'
        date = new Date(2013, 1, 1, 7, 0, 0)

        plugin.getData(deviceId, propertyName, date).then( (data) =>
          assert.deepEqual data, []
          finish()
        ).catch(finish)


      it 'should return the data', (finish) =>
        deviceId = 'test'
        propertyName = 't1'
        date = new Date(2013, 1, 1, 7, 0, 0)

        file = plugin.getPathOfLogFile deviceId, propertyName, date
        fs.mkdirsSync path.dirname(file)

        fs.writeFileSync file, """
          1359698400000,1.1
          1359699000000,2.3

        """

        plugin.getData(deviceId, propertyName, date).then( (data) =>
          assert.deepEqual data, [[1359698400000,1.1], [1359699000000,2.3]]
          finish()
        ).catch(finish)

      after =>
        fs.rmrfSync @dataloggerDir

    describe 'logData()', =>

      it 'should log the data to csv', (finish) =>
        deviceId = 'test'
        propertyName = 't1'
        date = new Date(2013, 1, 1, 7, 0, 0)

        file = plugin.getPathOfLogFile deviceId, propertyName, date

        plugin.logData(deviceId, propertyName, 4.2, date).then( =>
          assert fs.existsSync file
          data = fs.readFileSync file
          assert.equal data.toString(), "1359698400000,4.2\n"
          finish()
        ).catch(finish)      

      after =>
        fs.rmrfSync @dataloggerDir

    describe 'addLoggerForDevice()', =>

      it 'should add the first listener', =>
        listener = null

        @testDevice.on = (event, l) =>
          assert.equal "t1", event
          assert typeof l is "function"
          listener = l


        plugin.addLoggerForDevice @testDevice, ["t1"]

        assert plugin.deviceListener["test1"]?
        assert plugin.deviceListener["test1"].listener["t1"]?
        assert.equal listener, plugin.deviceListener["test1"].listener["t1"]

      it 'should add the second listener', =>
        listener = null

        @testDevice.on = (event, l) =>
          assert.equal "t2", event
          assert typeof l is "function"
          listener = l


        plugin.addLoggerForDevice @testDevice, ["t2"]

        assert plugin.deviceListener["test1"]?
        assert plugin.deviceListener["test1"].listener["t2"]?
        assert.equal listener, plugin.deviceListener["test1"].listener["t2"]


    describe 'removeLoggerForDevice()', =>
      removeListenerCalled = false

      beforeEach =>
        removeListenerCalled = false


      it 'should remove the first listener', =>

        @testDevice.removeListener = (event, l) =>
          assert.equal "t1", event
          assert typeof l is "function"
          removeListenerCalled = true


        plugin.removeLoggerForDevice @testDevice, ["t1"]

        assert plugin.deviceListener["test1"]?
        assert not plugin.deviceListener["test1"].listener["t1"]?
        assert plugin.deviceListener["test1"].listener["t2"]
        assert removeListenerCalled

      it 'should remove the second listener', =>

        @testDevice.removeListener = (event, l) =>
          assert.equal "t2", event
          assert typeof l is "function"
          removeListenerCalled = true


        plugin.removeLoggerForDevice @testDevice, ["t2"]

        assert not plugin.deviceListener["test1"]?
        assert removeListenerCalled

    describe "get /datalogger/info/:deviceId", =>

      it 'should get the info', (finish) =>

        @config.sensors = []

        getDeviceByIdCalled = false
        @frameworkDummy.getDeviceById = (id) =>
          assert id is 'testId'
          getDeviceByIdCalled = true
          return @testDevice

        expectedResult =
          loggingProperties:
            t1: false
            t2: false

        request(@app)
          .get('/datalogger/info/testId')
          .expect('Content-Type', /json/)
          .expect(200)
          .expect(expectedResult)
          .end( (err) =>
            if err then return finish err
            assert getDeviceByIdCalled
            finish()
          )

    describe "get /datalogger/add/:deviceId/:sensorValue", =>

      it 'should get the info', (finish) =>

        @config.sensors = []

        @testDevice.on = =>
        @testDevice.removeListener = =>

        getDeviceByIdCalled = false
        @frameworkDummy.getDeviceById = (id) =>
          assert id is 'testId'
          getDeviceByIdCalled = true
          return @testDevice

        request(@app)
          .get('/datalogger/add/testId/t1')
          .expect('Content-Type', /json/)
          .expect(200)
          .end( (err) =>
            if err then return finish err
            assert @config.sensors.length is 1
            finish()
          )

    describe "get /datalogger/remove/:deviceId/:sensorValue", =>

      it 'should get the info', (finish) =>

        @config.sensors = []

        getDeviceByIdCalled = false
        @frameworkDummy.getDeviceById = (id) =>
          assert id is 'testId'
          getDeviceByIdCalled = true
          return @testDevice

        request(@app)
          .get('/datalogger/remove/testId/t1')
          .expect('Content-Type', /json/)
          .expect(200)
          .end( (err) =>
            if err then return finish err
            assert @config.sensors.length is 0
            finish()
          )

    describe "get /datalogger/data/:deviceId/:sensorpropertyName", =>

      it 'should get the info', (finish) =>

        @config.sensors = []

        getDeviceByIdCalled = false
        @frameworkDummy.getDeviceById = (id) =>
          assert id is 'testId'
          getDeviceByIdCalled = true
          return @testDevice

        expectedResult =
          title:
            text: "test 1: t1"
          tooltip:
            valueDecimals: 2
          yAxis:
            labels:
              format: "{value}"
          series: [
            name: "Messwert"
            data: []
          ]


        request(@app)
          .get('/datalogger/data/testId/t1')
          .expect('Content-Type', /json/)
          .expect(200)
          .expect(expectedResult)
          .end( (err) =>
            if err then return finish err
            assert @config.sensors.length is 0
            finish()
          )