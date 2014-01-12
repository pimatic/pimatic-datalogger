pimatic datalogger
=======================

Allows you to log sensor data like temperature and humidity to da database and to show it on 
a nice graph on the mobile-frontend.

Example config:
---------------

    {
      "plugin": "datalogger",
      "sensors": [
        {
          "id": "pilight-work-temperature",
          "sensorValues": [
            "temperature",
            "humidity"
          ]
        }
      ]
    }

But you can also add the sensors to log at the mobile-frontend. Just click the sensor values there.