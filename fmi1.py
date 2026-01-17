#!/usr/bin/python
import fmi_weather_client as fmi
from fmi_weather_client.errors import ClientError, ServerError
import sys
import json
from datetime import datetime
import pytz
import math

try:
    searchword = sys.argv[1]
    ennustusOrNot = ""
    if (len(sys.argv) > 2):
        ennustusOrNot = sys.argv[2]
    if (ennustusOrNot == "ennustus"):

        weather = fmi.forecast_by_place_name(searchword, 12)
        if weather is not None:
            local_tz = pytz.timezone('Europe/Helsinki')
            # Convert the time to local timezone

            returndata = {
                "place": weather.place,
                "forecasts": {}
            }
            for item in weather.forecasts:
                returndata["forecasts"][item.time.strftime('%Y-%m-%d %H:%M')] = {
                    "time": item.time.astimezone(local_tz).strftime('%-d.%-m. %-H:%M'),
                    "temperature": f"{round(item.temperature.value)}{item.temperature.unit}",
                    "cloud_cover": f"{round(item.cloud_cover.value)}{item.cloud_cover.unit}",
                    "precipitation_amount": f"{round(item.precipitation_amount.value)}{item.precipitation_amount.unit}",
                    "wind_speed": round(item.wind_speed.value),
                    "wing_gust": item.wind_gust.value if not math.isnan(item.wind_gust.value) else "",
                    "feels_like": f"{round(item.feels_like.value)}{item.feels_like.unit}"
                }
            print(json.dumps(returndata))

    else:
        weather = fmi.weather_by_place_name(searchword)
        if weather is not None:
            local_tz = pytz.timezone('Europe/Helsinki')  # Replace with your local timezone
            local_time = weather.data.time.astimezone(local_tz)
            #print(weather.data.wind_gust.value)
            returndata = {
                "place": weather.place,
                "time": local_time.strftime('%H:%M'),
                "temperature": f"{weather.data.temperature.value}{weather.data.temperature.unit}",
                "humidity": f"{weather.data.humidity.value}{weather.data.humidity.unit}",
                "wind_speed": weather.data.wind_speed.value,
                "wind_direction": weather.data.wind_direction.value,
                "pressure": f"{weather.data.pressure.value}{weather.data.pressure.unit}",
                "precipitation_amount": f"{weather.data.precipitation_amount.value}{weather.data.precipitation_amount.unit}",
                "wind_gust": weather.data.wind_gust.value if not math.isnan(weather.data.wind_gust.value) else "",
                "cloud_cover": f"{weather.data.cloud_cover.value}{weather.data.cloud_cover.unit}",
                "feels_like": f"{round(weather.data.feels_like.value,1)}{weather.data.feels_like.unit}"
            }
            print(json.dumps(returndata))
except ClientError as err:
    print(json.dumps({"status": "error", "type": "client", "code": err.status_code, "message": err.message}))
except ServerError as err:
    print(json.dumps({"status": "error", "type" :"server", "code": err.status_code, "message": err.body}))
except Exception as err:
    print(json.dumps({"status": "exception", "type": "other", "message": str(err)}))
