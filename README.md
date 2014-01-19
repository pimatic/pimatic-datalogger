pimatic datalogger
=======================

Allows you to log sensor data like temperature and humidity to csv files and to show it on 
a nice graph on the mobile-frontend.

Example config:
---------------

    {
      "plugin": "datalogger",
      "devices": [
        {
          "id": "pilight-living-temperature",
          "attributes": [
            "temperature",
            "humidity"
          ]
        }
      ]
    }

But you can also add the sensors to log at the mobile-frontend. Just click the sensor values there.