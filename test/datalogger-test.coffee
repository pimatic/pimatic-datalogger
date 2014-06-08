module.exports = (env) ->

  assert = env.require "assert"
  express = env.require 'express'
  request = env.require 'supertest'

  fs = env.require 'fs.extra'
  os = require 'os'
  events = require 'events'
  path = require 'path'
  t = env.require('decl-api').types

  describe "datalogger", ->

    plugin = (require '../datalogger') env

    before =>
      @app = express()
      @frameworkDummy = new events.EventEmitter
      @frameworkDummy.maindir = "#{os.tmpdir()}/pimatic-test/mode_modules/pimatic"
      @config = {}
      fs.mkdirsSync @frameworkDummy.maindir
      @dataloggerDir = "#{os.tmpdir()}/pimatic-test/datalogger"

      @testDevice = new (
        class DummyDevice extends env.devices.Sensor
          id: "test1"
          name: "test 1"
      
          attributes:
            t1:
              description: "a test value"
              type: t.number
            t2:
              description: "another test value"
              type: t.number
      ) 




    after =>
      fs.rmrfSync @frameworkDummy.maindir

    describe '#init', =>

      it 'should init', =>
        plugin.init @app, @frameworkDummy, @config

        assert @config.devices
        assert Array.isArray @config.devices

    describe 'getDeviceConfig()', =>

      it 'should get the entry', =>
        @config.devices = [
          {
            id: "test"
            attributes: ["t1", "t2"]
          }
        ]

        entry = plugin.getDeviceConfig("test")
        assert entry?
        assert.deepEqual entry, @config.devices[0]

      it 'should not find the entry', =>
        @config.devices = [
          {
            id: "test"
            attributes: ["t1", "t2"]
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
        
        @config.devices = []
        expectedEntry = 
          id: "test"
          attributes: ["t1", "t2"]

        plugin.addDeviceToConfig "test", ["t1", "t2"]
        assert.deepEqual expectedEntry, @config.devices[0]
        assert saveConfigCalled

      it 'should add the sensor value', =>

        expectedEntry = 
          id: "test"
          attributes: ["t1", "t2", "t3"]

        plugin.addDeviceToConfig "test", ["t3"]
       
        assert.deepEqual expectedEntry, @config.devices[0]
        assert saveConfigCalled

      it 'should add the second sensor', =>

        expectedEntry = 
          id: "test2"
          attributes: ["t3"]

        plugin.addDeviceToConfig "test2", ["t3"]
       
        assert.equal 2, @config.devices.length
        assert.deepEqual expectedEntry, @config.devices[1]
        assert saveConfigCalled

    describe 'removeDeviceFromConfig()', =>
      
      saveConfigCalled = false
      beforeEach =>
        saveConfigCalled = false
        @frameworkDummy.saveConfig = =>
          saveConfigCalled = true

      it 'should remove the entry', =>

        @config.devices = [
          {
            id: "test"
            attributes: ["t1", "t2"]
          }
        ]

        plugin.removeDeviceFromConfig "test", ["t1", "t2"]
        assert.equal 0, @config.devices.length
        assert saveConfigCalled

      it 'should remove a sensorValue', =>

        @config.devices = [
          {
            id: "test"
            attributes: ["t1", "t2"]
          }
        ]

        expectedEntry = 
          id: "test"
          attributes: ["t1"]


        plugin.removeDeviceFromConfig "test", ["t2"]
        assert.equal 1, @config.devices.length
        assert.deepEqual expectedEntry, @config.devices[0]
        assert saveConfigCalled

    describe 'getPathOfLogFile()', =>

      it 'should return the right path', =>
        file = plugin.getPathOfLogFile 'test', 't1', new Date(2013, 1, 1, 7, 0, 0)
        assert.equal file, "#{@dataloggerDir}/test/t1/2013/02/01.csv"


    describe 'getData()', =>

      it 'should return a empty array', (finish) =>
        deviceId = 'test'
        attributeName = 't1'
        date = new Date(2013, 1, 1, 7, 0, 0)

        plugin.getData(deviceId, attributeName, date).then( (data) =>
          assert.deepEqual data, []
          finish()
        ).catch(finish)


      it 'should return the data', (finish) =>
        deviceId = 'test'
        attributeName = 't1'
        date = new Date(2013, 1, 1, 7, 0, 0)

        file = plugin.getPathOfLogFile deviceId, attributeName, date
        fs.mkdirsSync path.dirname(file)

        fs.writeFileSync file, """
          1359698400000,1.1
          1359699000000,2.3

        """

        plugin.getData(deviceId, attributeName, date).then( (data) =>
          assert.deepEqual data, [[1359698400000,1.1], [1359699000000,2.3]]
          finish()
        ).catch(finish)

      after =>
        fs.rmrfSync @dataloggerDir


    describe 'getDataInRange()', =>

      it 'should return data from 2020/1/2 to 2021/7/2', (finish) =>
        deviceId = 'test'
        attributeName = 't1'
        from = new Date(2020, 0, 1)
        to = new Date(2021, 6, 2)

        if fs.existsSync @dataloggerDir
          fs.rmrfSync @dataloggerDir

        makeFile = (year, month, day, i) =>
          date = new Date(year, month-1, day, 0, 0, 0)
          file = plugin.getPathOfLogFile 'test', 't1', date
          data = "#{date.getTime()}, #{i}"  
          fs.mkdirsSync path.dirname(file)
          fs.writeFileSync file, data

        makeFile 2019, 1, 1, 0 #no
        makeFile 2020, 1, 2, 1 #yes
        makeFile 2020, 1, 3, 2 #yes
        makeFile 2020, 3, 6, 3 #yes
        makeFile 2020, 6, 2, 4 #yes
        makeFile 2021, 7, 2, 5 #yes
        makeFile 2021, 7, 3, 6 #no

        expectedData = [
          [ 1577919600000, 1 ],
          [ 1578006000000, 2 ],
          [ 1583449200000, 3 ],
          [ 1591048800000, 4 ],
          [ 1625176800000, 5 ] 
        ]


        plugin.getDataInRange(deviceId, attributeName, from, to).then( (data) =>
          assert.deepEqual data, expectedData
          finish()
        ).catch(finish)


    describe 'logData()', =>

      it 'should log the data to csv', (finish) =>
        deviceId = 'test'
        attributeName = 't1'
        date = new Date(2013, 1, 1, 7, 0, 0)

        file = plugin.getPathOfLogFile deviceId, attributeName, date

        plugin.logData(deviceId, attributeName, 4.2, date).then( =>
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

        @config.devices = []

        getDeviceByIdCalled = false
        @frameworkDummy.getDeviceById = (id) =>
          assert id is 'testId'
          getDeviceByIdCalled = true
          return @testDevice

        expectedResult =
          loggingAttributes:
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

        @config.devices = []

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
            assert @config.devices.length is 1
            finish()
          )

    describe "get /datalogger/remove/:deviceId/:sensorValue", =>

      it 'should get the info', (finish) =>

        @config.devices = []

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
            assert @config.devices.length is 0
            finish()
          )

    describe "get /datalogger/data/:deviceId/:sensorattributeName", =>

      it 'should get the info', (finish) =>

        @config.devices = []

        getDeviceByIdCalled = false
        @frameworkDummy.getDeviceById = (id) =>
          assert id is 'testId'
          getDeviceByIdCalled = true
          return @testDevice

        expectedResult =
          data: []

        request(@app)
          .get('/datalogger/data/testId/t1')
          .expect('Content-Type', /json/)
          .expect(200)
          .expect(expectedResult)
          .end( (err) =>
            if err then return finish err
            assert @config.devices.length is 0
            finish()
          )