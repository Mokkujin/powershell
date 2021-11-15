# SQL_Database.ps1

* create a backup of databases or single database
* restore single database

## requirements

* admin privileges
* SQLPS
* enough storage to save the backup
* enough time to create the backup ;)

---
## usage

* create a backup of all databases to Path C:\Backup\
```powershell
.\SQL_Database.ps1 -Backup -Database FULL -Path C:\Backup\
```

* create a backup of the database DB-TEST-01 to Path C:\Backup\
```powershell
.\SQL_Database.ps1 -Backup -Database DB-TEST-01 -Path C:\Backup\
```

* create a backup of the database DB-TEST-01 to Path C:\Backup\ and write to Logfile C:\TEMP\SQL.log default is logging to eventlogs ( Application -> SQLDatabaseScript )
```powershell
.\SQL_Database.ps1 -Backup -Database DB-TEST-01 -Path C:\Backup\ -Logfile C:\TEMP\SQL.log
```

* restore the database DB-TEST-01 from Path C:\Backup\20211106235801-DB-TEST-01.backup
```powershell
.\SQL_Database.ps1 -Restore -Database DB-TEST-01 -Path C:\Backup\20211106235801-DB-TEST-01.backup -Verbose
```

---
## parameters

```- Backup```
create backup of database

```- Restore```
restore a database

```- Database```
name of the database

used with backup = create a backup of database

used with restore = do an restore of database (existsing database will be overwritten)

```- Path```

if you use path with the switch backup, all backups will be stored there

if you use path with the switch restore, this backup file will be used to overwrite the database given in ```- Database```

```- Logfile```
if you not use this switch all logentry will go to Application -> SQLDatabaseScript, otherwise the logentry will be written to the given logfile    

---