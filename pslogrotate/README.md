# pslogrotate.ps1

in linux there is an tool called logrotate to rotate all logs for diffrent applications, this is a small copy of this tool for windows
      
if you call the script without parameter -Config , the configfile should placed in the same folder as the script

first you have to create a json file to configure the rotation

### example
```json
{
    "compress": "1",
    "retention": "5",
    "log": [
      {
        "name": "Barrier",
        "service": "Barrier",
        "path": "I:\\LogFiles\\Runtime.log",
        "retention": "10",
        "compress": "1",
        "restart": "1",
        "type": "single"
      },
      {
        "name": "ServiceName",
        "service": "ServiceName",
        "path": "I:\\App\\*.log",
        "restart": "1",
        "type": "multi"
      }
    ]
  }
```

the keys **compress** and **retention** must be configure in the global section !

you dont have to configure it on each logfile but you can overwrite the global keys , see example ;)

if you dont use the parameter **_-Config_** the configfile must be stored on the same location as the script

### example

run without config parameter
```powershell
.\pslogrotate.ps1
```

run with config parameter
```powershell
.\pslogrotate.ps1 -Config C:\Temp\config.json
```

## How does it work ?

Here a short explanation about the Configuration.

compress and retention must be configured all the time in the global section

| Variable | Description |
| ---- | ---- |
| name | DisplayName of the Service |
| service | Name of the service (use Get-Service to show the real name) |
| path | Path to the Logfile incl filename / wildflag (if you use a wildflag the parameter type has to been set to multi) |
| retention | how long should the logfile exists on harddrive ( timespan is in days !) |
| compress | should the logfile been compressed ? | 
| restart | selects whether the service should be restarted before the logfile is rotated |
| type | is it a single file or multiple files stored in the path (see example) |