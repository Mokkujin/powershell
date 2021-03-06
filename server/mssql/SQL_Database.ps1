#Requires -RunAsAdministrator
#Requires -Version 5.1

<#
    .SYNOPSIS
    Make SQL Backup and Restore easier
    .DESCRIPTION
    make the backup and the restore of databases easier
    ! Watch out restore overwrite an database !
    .PARAMETER Backup
    to create a backup
    .PARAMETER Restore
    to create an restore (ATTENTION AN RESTORE OVERWRITES THE DATABASE)
    .PARAMETER Database
    if you want to backup a single database set the name of the database , if you want to create a backup of all databases use full
    .PARAMETER Path
    where should i store the backup files 
    .PARAMETER Logfile
    logfile (incl. path) if set the log go to an file otherwise the log will go to eventlog 'Application' 'SQL_Database'
    .EXAMPLE
    PS C:\> .\SQL_Database.ps1 -Backup -Database FULL -Path C:\Backup\

    create a backup of all databases to Path C:\Backup\
    .EXAMPLE
    PS C:\> .\SQL_Database.ps1 -Backup -Database DB-TEST-01 -Path C:\Backup\

    create a backup of the database DB-TEST-01 to Path C:\Backup\
    .EXAMPLE
    PS C:\> .\SQL_Database.ps1 -Backup -Database DB-TEST-01 -Path C:\Backup\ -Logfile C:\TEMP\SQL.log

    create a backup of the database DB-TEST-01 to Path C:\Backup\ and write to Logfile C:\TEMP\SQL.log
    .EXAMPLE
    PS C:\> .\SQL_Database.ps1 -Restore -Database DB-TEST-01 -Path C:\Backup\20211106235801-DB-TEST-01.backup -Verbose

    restore the database DB-TEST-01 from Path C:\Backup\20211106235801-DB-TEST-01.backup
    .LINK
    https://github.com/Mokkujin/powershell/tree/main/server/mssql
    .NOTES
    original version by C.Pope
#>

[CmdletBinding(ConfirmImpact = 'Low')]
param
(
    [Parameter(ParameterSetName = 'Backup',
        ValueFromPipeline,
        ValueFromPipelineByPropertyName)]
    [Parameter(ParameterSetName = 'Restore')]
    [ValidateNotNullOrEmpty()]
    [string]
    $Database = $null,
    [Parameter(ParameterSetName = 'Backup',
        ValueFromPipeline,
        ValueFromPipelineByPropertyName)]
    [Parameter(ParameterSetName = 'Restore')]
    [ValidateNotNullOrEmpty()]
    [string]
    $Path = $null,
    [Parameter(ParameterSetName = 'Backup',
        ValueFromPipeline,
        ValueFromPipelineByPropertyName)]
    [Parameter(ParameterSetName = 'Restore')]
    [ValidateNotNullOrEmpty()]
    [string]
    $Logfile = $null,
    [Parameter(ParameterSetName = 'Backup',
        ValueFromPipeline,
        ValueFromPipelineByPropertyName,
        HelpMessage = 'Backup a Database')]
    [switch]$Backup,
    [Parameter(ValueFromPipeline,
        ParameterSetName = 'Restore',
        ValueFromPipelineByPropertyName,
        HelpMessage = 'Restore a Database')]
    [switch]$Restore
)

#region Vars
$script:useeventlog = $false
$script:GLBLogfile = $Logfile
#endregion Vars

#region ImportModuleSQLPS
try
{
    Import-Module -Name SQLPS -ErrorAction Stop
}
catch
{
    Write-Error -Message 'Could not Import Module SQLPS'
    exit 1
}
#endregion ImportModuleSQLPS

#region Functions

#region WriteLogfile
function Write-Logfile
{
    <#
    .SYNOPSIS
    write a logfile
    .DESCRIPTION
    write a logfile
    .PARAMETER Message
    message to write
    .PARAMETER Status
    status of entry 
    .EXAMPLE
    PS C:\> Write-LogFile -Message 'TEST' -Status 1

    write a info message
    .EXAMPLE
    PS C:\> Write-LogFile -Message 'TEST' -Status 2

    write a warning message
    .EXAMPLE
    PS C:\> Write-LogFile -Message 'TEST' -Status 3

    write a error message
#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, 
            ValueFromPipeline, 
            ValueFromPipelineByPropertyName)]
        [string]$Message,
        [Parameter(ValueFromPipeline, 
            ValueFromPipelineByPropertyName)]
        [int]$Status
    )

    switch ($Status)
    {
        1
        { 
            $StatusStr = 'INFO'
            $StatusEvt = 'Information'
            $EvtID = '1001' 
        }
        2
        { 
            $StatusStr = 'WARN' 
            $StatusEvt = 'Warning' 
            $EvtID = '1002' 
        }
        3
        { 
            $StatusStr = 'ERROR' 
            $StatusEvt = 'Error' 
            $EvtID = '1003'
        }
        Default
        { 
            $StatusStr = 'INFO' 
            $StatusEvt = 'Information' 
            $EvtID = '1001' 
        }
    }

    $LogEntry = ('| {0} - {1,-5} | {2} ' -f (Get-Date -Format 'dd.MM.yyyy HH:mm:ss'), $StatusStr, $Message)
    Write-Verbose -Message $LogEntry

    if (($Message) -and ($script:useeventlog -eq $false))
    {
        Add-Content -Path $script:GLBLogfile -Value $LogEntry
    }

    Write-Verbose ('USEEVENTLOG {0}' -f $script:useeventlog)

    if ($script:useeventlog)
    {
        $ParaEventMessage = @{
            LogName     = 'Application'
            Source      = 'SQLDatabaseScript'
            EntryType   = $StatusEvt
            Message     = $LogEntry
            EventID     = $EvtID
        }
        Write-EventLog @ParaEventMessage -ErrorAction Stop
    }
}
#endregion WriteLogfile

#region CreateBackup
function New-Backup
{
    <#
    .SYNOPSIS
    create a backup from an database
    .DESCRIPTION
    create a backup from an database
    .PARAMETER FuncDB
    Name of the Database , if you use FULL all Databases get an backup
    .PARAMETER Location
    where should i store the file
    .EXAMPLE
    PS C:\> New-Backup -FuncDB $Database -Location $Path

    Create a Backup from $Database an save to location $Path
#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, 
            ValueFromPipeline, 
            ValueFromPipelineByPropertyName)]
        [string]$FuncDB,
        [Parameter(Mandatory, 
            ValueFromPipeline, 
            ValueFromPipelineByPropertyName)]
        [string]$Location
    )
    # get all Databases
    try
    {
        $AllDatabases = (Get-ChildItem -Path SQLSERVER:\SQL\localhost\DEFAULT\DATABASES -ErrorAction Stop)
        Write-Logfile -Message 'get Databases from SQL Server'
    }
    catch
    {
        $Message = 'could not get Databases from SQL Server'
        Write-LogFile -Message $Message -Status 3
    }

    # check if location is a path if not try to export from give string
    if (-not (Test-Path -Path $Location -PathType Container -ErrorAction Stop))
    {
        $Location = ((Get-Item -Path $Location).DirectoryName)
    }

    # check if folder exists
    If (-not (Test-Path -Path $Location -PathType Container -ErrorAction Stop))
    {
        try
        {
            $null = (New-Item -Path $Location -ItemType Directory -Confirm $false -ErrorAction Stop)
        }
        catch
        {
            $Message = ('could not create folder {0}' -f $Location)
            Write-Logfile -Message $Message -Status 2
            Write-Error -Message $Message -Category 18
            exit 5
        }
        finally
        {
            #region GarbageCollection
            [GC]::Collect()
            [GC]::WaitForPendingFinalizers()
            [GC]::Collect()
            [GC]::WaitForPendingFinalizers()
            #endregion GarbageCollection
        }
    }

    If ($FuncDB.ToLower() -eq 'full')
    {
        # create backup for each Database
        foreach ($SingleDatabase in $AllDatabases)
        {
            $BackupFile = ('{0}\{1}-{2}.backup' -f $Location, (Get-Date -Format 'yyyyMMddHHmmss'), $SingleDatabase.Name)
            try
            {
                $ParaBackup = @{
                    ServerInstance = '.' 
                    Database       = $SingleDatabase.Name
                    BackupFile     = $BackupFile
                }
                $null = (Backup-SqlDatabase @ParaBackup -Confirm:$false -ErrorAction Stop)
                Write-Logfile -Message $('backup of database {0} created' -f $SingleDatabase.Name) 
            }
            catch
            {
                Write-Logfile -Message ('could not backup database {0}' -f $SingleDatabase.Name) -Status 3
            }
            finally
            {
                #region GarbageCollection
                [GC]::Collect()
                [GC]::WaitForPendingFinalizers()
                [GC]::Collect()
                [GC]::WaitForPendingFinalizers()
                #endregion GarbageCollection
            }
        }
    }
    else
    {
        # check if Database exists
        if ($AllDatabases -match $FuncDB)
        {
            Write-Logfile -Message $('Backup Databases {0} from SQL Server' -f $FuncDB)
            $BackupFile = ('{0}\{1}-{2}.backup' -f $Location, (Get-Date -Format 'yyyyMMddHHmmss'), $FuncDB)
            try
            {
                $ParaBackup = @{
                    ServerInstance = '.'
                    Database       = $FuncDB
                    BackupFile     = $BackupFile
                }
                $null = (Backup-SqlDatabase @ParaBackup -Confirm:$false -ErrorAction Stop)
                Write-Logfile -Message $('backup of database {0} created' -f $FuncDB)
            }
            catch
            {
                Write-Logfile -Message $('could not backup database {0}' -f $FuncDB) -Status 3
            }
            finally
            {
                #region GarbageCollection
                [GC]::Collect()
                [GC]::WaitForPendingFinalizers()
                [GC]::Collect()
                [GC]::WaitForPendingFinalizers()
                #endregion GarbageCollection
            }
        }
        else
        {
            Write-Logfile -Message $('Skip database {0} not found' -f $FuncDB) -Status 2
        }
    }
}
#endregion CreateBackup

#region DoRestore
function New-Restore
{
    <#
    .SYNOPSIS
    restore a database from file
    .DESCRIPTION
    restore a database from file
    .PARAMETER FuncDB
    restore the database with this name, ATTENTION THE DATABASE WILL BE OVERWRITTEN
    .PARAMETER Location
    where should i read the file
    .EXAMPLE
    PS C:\> New-Restore -FuncDB $Database -Location $Path
    
    Restore the $Database from Location $Path (Path must be a backupfile)
#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, 
            ValueFromPipeline, 
            ValueFromPipelineByPropertyName)]
        [string]$FuncDB,
        [Parameter(Mandatory, 
            ValueFromPipeline, 
            ValueFromPipelineByPropertyName)]
        [string]$Location
    )

    # check if exists
    if (Test-Path -Path $Location -PathType Leaf)
    {
        try
        {
            $ParaRestore = @{
                ServerInstance  = '.'
                Database        = $FuncDB
                BackupFile      = $Location
                ReplaceDatabase = $true
                Confirm         = $true
            }
            $null = (Restore-SqlDatabase @ParaRestore -ErrorAction Stop)
            $Message = ('Database {0} restored' -f $FuncDB)
            Write-Logfile -Message $Message
        }
        catch
        {
            $Message = ('could not restore database {0}' -f $FuncDB)
            Write-Logfile -Message $Message -Status 3
            Write-Error -Message $Message
            exit 10           
        }
        finally
        {
            #region GarbageCollection
            [GC]::Collect()
            [GC]::WaitForPendingFinalizers()
            [GC]::Collect()
            [GC]::WaitForPendingFinalizers()
            #endregion GarbageCollection
        }
    }
    else
    {
        $Message = ('Restore File {0} do not exists' -f $Path)
        Write-Logfile $Message -Status 3
        Write-Error -Message $Message -Category 13
        exit 6
    }
}
#endregion DoRestore

#endregion Functions


#region CreateLogger
if ($script:Logfile)
{
    $script:useeventlog = $false
}
else
{
    # Check if EventLog Source available
    try
    {
        $null = (Get-EventLog -LogName 'Application' -Source 'SQLDatabaseScript' -ErrorAction Stop)
        $msg = ('Namespace -SQLDatabaseScript- exists in -Application-')
        Write-Logfile -Message $msg
        $script:useeventlog = $true
    }
    catch
    {
        try
        {
            $null = (New-EventLog -LogName 'Application' -Source 'SQLDatabaseScript' -ErrorAction Stop)   
            $msg = ('Namespace -SQLDatabaseScript- created in -Application-')
            Write-Logfile -Message $msg
            $script:useeventlog = $true
            Write-Logfile -Message 'First Run'  
        }
        catch
        {
            Write-Error -Message $('Could not create Namespace -SQLDatabaseScript- in -Application- Log' -f $NameLog, $NameSource)
            #region GarbageCollection
            [GC]::Collect()
            [GC]::WaitForPendingFinalizers()
            [GC]::Collect()
            [GC]::WaitForPendingFinalizers()
            #endregion GarbageCollection
        }
    }  
    
}
#endregion CreateLogger

Write-Logfile -Message 'Start Backup'

# check if Backup and Restore is set
If (($Backup) -and ($Restore))
{
    Write-Error -Message 'You cannot create a Backup and do an Restore in the same Task ! use -Backup OR -Restore' -Category 6
    exit 2
}

#region CreateBackup
If (($Backup) -and (-not ($Path)))
{
    Write-Error -Message $('Cannot Backup Database without Backup Location. use -Path' -f $Database) -Category 6
    exit 3
}
If (($Backup) -and ($Path))
{
    New-Backup -FuncDB $Database -Location $Path    
}
#endregion

#region CreateRestore
# check if Restore an Restore File is set , cannot restore a database without dump ;=)
If (($Restore) -and (-not ($Path)))
{
    Write-Error -Message $('Cannot Restore Database {0} without Backup File , plz define -File' -f $Database) -Category 6
    exit 4
}

# do an restore if both set           
If (($Restore) -and ($Path))
{
    New-Restore -FuncDB $Database -Location $Path    
}
#endregion

Write-Logfile -Message 'End Backup'