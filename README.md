# HomeAssistant.spoon

```lua
ha = spoon.HomeAssistant:configure({
    entity_name = "my_laptop",
    url = "http://192.168.0.42:8123",
    token = "your-user-token",
}):start()
```

## Exposed entities

- binary_sensor.work_laptop_battery_charging
- binary_sensor.work_laptop_locked
- binary_sensor.work_laptop_microphone_in_use
- binary_sensor.work_laptop_plugged
- binary_sensor.work_laptop_screens
- binary_sensor.work_laptop_screensaver
- binary_sensor.work_laptop_system
- sensor.work_laptop_battery
- sensor.work_laptop_battery_time_full_charge
- sensor.work_laptop_battery_time_remaining
- sensor.work_laptop_ssid
