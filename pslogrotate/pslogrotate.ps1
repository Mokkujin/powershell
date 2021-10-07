#Requires -Version 5.0 -RunAsAdministrator
<#
      .SYNOPSIS
      Rotate Logs on Server

      .DESCRIPTION
      in linux there is an tool called logrotate to rotate all logs for diffrent applications, this is a small copy of this tool for windows
      if you call the script without parameter -Config , the configfile should placed in the same folder as the script

      .EXAMPLE
      PS C:\> .\pslogrotate.ps1

      .EXAMPLE
      PS C:\> .\pslogrotate.ps1 -Config pslogrotate.json

      .LINK
      GITHUB

      .NOTES
      original version by pope
#>
[CmdletBinding(ConfirmImpact = 'Low',
   SupportsShouldProcess)]
param
(
   [Parameter(ValueFromPipeline,
      ValueFromPipelineByPropertyName)]
   [ValidateNotNullOrEmpty()]
   [string]
   $Config = './pslogrotate.json'
)

#region functions
function Out-LogFileCompress
{
   <#
         .SYNOPSIS
         compress the logfile and delete the original one

         .DESCRIPTION
         compress the logfile and delete the original one

         .PARAMETER FuncFile
         the logfile to check -FuncFile.

         .EXAMPLE
         Out-LogFileCompress -FuncFile C:\App\log\logfile.log
   #>


   [CmdletBinding(ConfirmImpact = 'None')]
   param (
      [Parameter(Mandatory, HelpMessage = 'Add help message for user')]
      [string]
      $FuncFile
   )

   if (Test-Path -Path $FuncFile -PathType Leaf -ErrorAction SilentlyContinue)
   {
      $FileName = (Split-Path -Path $FuncFile -Leaf)
      $FileNameCompressed = $FuncFile + '.zip'
      $CompressFile = @{
         LiteralPath      = $FuncFile
         CompressionLevel = 'Fastest'
         DestinationPath  = $FileNameCompressed
      }

      #compress logfile
      try
      {
         Compress-Archive @CompressFile
         $msg = ('Compress logfile {0} to archive {1}' -f $FileName, $FileNameCompressed)
         Write-Verbose -Message $msg
         Write-EventLog -LogName 'Application' -Source 'pslogrotate' -EntryType Information -EventId 1001 -Message $msg -ErrorAction Continue
      }
      catch
      {
         $msg = ('Could not compress logfile {0}' -f $FileName)
         Write-Verbose -Message $msg
         Write-EventLog -LogName 'Application' -Source 'pslogrotate' -EntryType Error -EventId 2003 -Message $msg -ErrorAction Continue
      }

      # remove uncompressed logfile
      try
      {
         $null = (Remove-Item -Path $FuncFile -Force -ErrorAction Stop)
      }
      catch
      {
         $msg = ('logfile {0} could not be deleted' -f $FuncFile)
         Write-Verbose -Message $msg
         Write-EventLog -LogName 'Application' -Source 'pslogrotate' -EntryType Error -EventId 2010 -Message $msg -ErrorAction Continue
      }
   }
   else
   {
      $msg = ('logfile {0} does not exists / or not accessable' -f $FileName)
      Write-Verbose -Message $msg
      Write-EventLog -LogName 'Application' -Source 'pslogrotate' -EntryType Error -EventId 2004 -Message $msg -ErrorAction Continue
   }
}

function Remove-OldLogFiles
{
   <#
         .SYNOPSIS
         remove old logfile 

         .DESCRIPTION
         check the logfile use the retention from config file

         .PARAMETER FuncFile
         the logfile to check -FuncFile.

         .PARAMETER FuncRetention
         the retention time in Days -FuncRetention.

         .EXAMPLE
         Remove-OldLogFiles -FuncFile C:\App\log\logfile.log -FuncRetention 30
   #>


   [CmdletBinding(ConfirmImpact = 'None')]
   param (
      [Parameter(Mandatory, HelpMessage = 'File to Remove')]
      [string]
      $FuncFile,
      [Parameter(Mandatory, HelpMessage = 'Retention in Days')]
      [string]
      $FuncRetention
   )

   if (Test-Path -Path $FuncFile -PathType Leaf -ErrorAction SilentlyContinue)
   {
      # check creation time
      $CreationTime = (Get-Item -Path $FuncFile -ErrorAction Stop).CreationTime 

      # Check File Date if older then retention Remove it
      $TimeSpan = (New-TimeSpan -Days $FuncRetention)

      if (((Get-Date) - $CreationTime) -gt $TimeSpan)
      {
         # remove file
         $msg = ('logfile {0} is older then {1} Days - remove it' -f $FuncFile, $FuncRetention)
         Write-Verbose -Message $msg
         Write-EventLog -LogName 'Application' -Source 'pslogrotate' -EntryType Information -EventId 1004 -Message $msg -ErrorAction Continue

         try
         {
            $null = (Remove-Item -Path $FuncFile -Force -ErrorAction Stop) 
            
            $Return = $true
         }
         catch
         {
            $msg = ('logfile {0} could not be deleted' -f $FuncFile)
            Write-Verbose -Message $msg
            Write-EventLog -LogName 'Application' -Source 'pslogrotate' -EntryType Error -EventId 2006 -Message $msg -ErrorAction Continue
            $Return = $false
         }
      }
      else
      {
         $Return = $false
      }
   }
   else
   {
      $msg = ('logfile {0} does not exists / or not accessable' -f $FileName)
      Write-Verbose -Message $msg
      Write-EventLog -LogName 'Application' -Source 'pslogrotate' -EntryType Error -EventId 2005 -Message $msg -ErrorAction Continue
      # to make sure the script will do the next job
      $Return = $true
   }

   $FuncFile = $null
   $Return
}

function Watch-LogFile
{
   <#
         .SYNOPSIS
         check the given file and rename it

         .DESCRIPTION
         check the given file and rename it

         .PARAMETER LogPath
         Path to Logfile

         .PARAMETER LogRetention
         Retention of the file in DAYS !

         .PARAMETER LogCompress
         should the logfile be compressed ? 0 = no 1 = yes 

         .EXAMPLE
         Watch-LogFile -LogPath C:\App\log\logfile.log -LogRetention 30 -LogCompress 1
   #>


   [CmdletBinding(ConfirmImpact = 'None')]
   param (
      [Parameter(Mandatory, HelpMessage = 'Path incl File to Logfile')]
      [string]
      $LogPath,
      [Parameter(Mandatory, HelpMessage = 'Retention in Days')]
      [string]
      $LogRetention,
      [Parameter(Mandatory, HelpMessage = 'Compress File ? 1 = yes 0 = no')]
      [string]
      $LogCompress
   )

   if (Test-Path -Path $LogPath -PathType Leaf)
   {
      $FileHash = ((Get-FileHash -Path $LogPath -Algorithm MD5 -ErrorAction Stop).Hash).Substring(2, 8)
      $FilePath = (Split-Path -Path $LogPath)
      $FileName = (Split-Path -Path $LogPath -Leaf)
      $FileExt = (Get-Item -Path $LogPath).Extension
      $NewFileName = ('{0}_{1}{2}{3}' -f $FileName, (Get-Date -UFormat '%Y%d%m%H%M'), $FileHash, $FileExt)
      
      $FileRemoved = (Remove-OldLogFiles -FuncFile $LogPath -FuncRetention $LogRetention)

      if ($FileRemoved -eq $false)
      {
         try
         {
            # Rename Logfile 
            $null = (Rename-Item -Path $LogPath -NewName $NewFileName -ErrorAction Stop)
            $msg = ('logfile {0} renamed to {1}' -f $FileName, $NewFileName)
            Write-Verbose -Message $msg
            Write-EventLog -LogName 'Application' -Source 'pslogrotate' -EntryType Information -EventId 1009 -Message $msg -ErrorAction Continue
         }
         catch
         {
            $msg = ('logfile {0} could not be renamed' -f $LogPath)
            Write-Verbose -Message $msg
            Write-EventLog -LogName 'Application' -Source 'pslogrotate' -EntryType Error -EventId 2009 -Message $msg -ErrorAction Continue
         }


         if ($LogCompress -eq '1')
         {
            $NewFilePath = $FilePath + '\' + $NewFileName
            $null = (Out-LogFileCompress -FuncFile $NewFilePath)
         }
      }
   }
   else
   {
      $msg = ('logfile {0} does not exists' -f $LogPath)
      Write-Verbose -Message $msg
      Write-EventLog -LogName 'Application' -Source 'pslogrotate' -EntryType Warning -EventId 2009 -Message $msg -ErrorAction Stop
   }
}
#endregion functions

# Check if EventLog Source available
try
{
   $null = (Get-EventLog -LogName 'Application' -Source 'pslogrotate' -ErrorAction Stop)
}
catch
{
   try
   {
      $null = (New-EventLog -LogName 'Application' -Source 'pslogrotate' -ErrorAction Stop)   
   }
   catch
   {
      Write-Error 'Could not create Namespace in Application Log'
   }
}

# Read Config from Json File

if (Test-Path -Path $Config -PathType Leaf)
{
   try
   {
      $JsonConfig = (Get-Content -Path $Config -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop)
   }
   catch
   {
      $msg = ('Could not read config file {0}' -f $Config)
      Write-Error -Message $msg
      Write-EventLog -LogName 'Application' -Source 'pslogrotate' -EntryType Error -EventId 2001 -Message $msg -ErrorAction Continue
      exit 1
   }
}

try
{
   $Compress = $JsonConfig.compress
   $Retention = $JsonConfig.retention
}
catch
{
   $msg = ('you have to define the global keys compress and retiontion in the global section of the configfile {0}' -f $Config)
   Write-Error -Message $msg
   Write-EventLog -LogName 'Application' -Source 'pslogrotate' -EntryType Error -EventId 2002 -Message $msg -ErrorAction Continue
   exit 2
}

foreach ($log in $JsonConfig.log)
{
   #$LGName = $Log.Name
   $LGService = $log.Service
   $LGRetention = $log.Retention
   $LGCompress = $log.Compress
   $LGPath = $log.Path
   $LGRestart = $log.Restart
   $LGType = $log.Type

   # Check Empty JSON Keys and set Global Config
   if (-not ($LGCompress))
   {
      $LGCompress = $Compress
   }

   if (-not ($LGRetention))
   {
      $LGRetention = $Retention
   }

   # Stop Service if needed
   if ($LGRestart -eq '1')
   {
      try
      {
         # Stop Service to rotate Logfile (if configured)
         $msg = ('stop service {0}' -f $LGService)
         Write-Verbose -Message $msg
         $null = (Stop-Service -Name $LGService -Force -Confirm:$false -ErrorAction Stop -WarningAction SilentlyContinue)
      }
      catch
      {
         $msg = ('could not stop service {0}' -f $LGService)
         Write-Verbose -Message $msg
         Write-EventLog -LogName 'Application' -Source 'pslogrotate' -EntryType Error -EventId 2007 -Message $msg -ErrorAction Continue
      }
   }

   switch ($LGType)
   {
      single
      {
         $null = (Watch-LogFile -LogPath $LGPath -LogRetention $LGRetention -LogCompress $LGCompress -ErrorAction Stop)

         # check zip files
         if ($LGCompress -eq '1')
         {
            $FilePath = (Split-Path -Path $LGPath -ErrorAction Stop)
            $FileName = (Split-Path -Path $LGPath -Leaf -ErrorAction Stop)
            $AllZipFiles = ((Get-ChildItem -Path $FilePath -Filter '*.zip' -ErrorAction Stop).Name)

            foreach ($ZipFile in $AllZipFiles)
            {
               $FileExt = ($FileExt -Replace '\*', '')

               if (($ZipFile -Match $FileExt) -and ($ZipFile.Contains($FileName)))
               {
                  $FileToCheck = $FilePath + '\' + $ZipFile
                  Write-Verbose -Message $FileToCheck
                  $null = (Remove-OldLogFiles -FuncFile $FileToCheck -FuncRetention $LGRetention -ErrorAction Stop)
               }
            }
         }
      }
      multi
      {
         # get path and check
         try
         {
            $FilePath = (Split-Path -Path $LGPath -ErrorAction Stop)    
         }
         catch
         {
            $msg = ('could not get path to logfile {0}' -f $LGPath)
            Write-Verbose -Message $msg
            Write-EventLog -LogName 'Application' -Source 'pslogrotate' -EntryType Error -EventId 2007 -Message $msg -ErrorAction Continue
            break
         }
         
         # get file extension
         $SplitPath = $LGPath.Split('\')
         $FileExt = $SplitPath[-1]

         if (Test-Path -Path $FilePath -PathType Container -ErrorAction SilentlyContinue)
         {
            Write-Verbose -Message ('Use File Filter : {0}' -f $FileExt)
            $AllFiles = ((Get-ChildItem -Path $FilePath -Filter $FileExt -ErrorAction Stop).Name)

            foreach ($LogToCheck in $AllFiles)
            {
               $FileToCheck = $FilePath + '\' + $LogToCheck
               $null = (Watch-LogFile -LogPath $FileToCheck -LogRetention $LGRetention -LogCompress $LGCompress -ErrorAction Stop)
            }
         }

         if ($LGCompress -eq '1')
         {
            try
            {
               $AllZipFiles = ((Get-ChildItem -Path $FilePath -Filter '*.zip' -ErrorAction Stop).Name)
            }
            catch
            {
               $msg = ('could not get any compressed logfiles in {0}' -f $FilePath)
               Write-Verbose -Message $msg
               Write-EventLog -LogName 'Application' -Source 'pslogrotate' -EntryType Error -EventId 2007 -Message $msg -ErrorAction Continue
            }
            

            foreach ($ZipFile in $AllZipFiles)
            {
               $FileExt = ($FileExt -Replace '\*', '')

               if (($ZipFile -Match $FileExt))
               {
                  # check zip files
                  $FileToCheck = $FilePath + '\' + $ZipFile
                  Write-Verbose -Message $FileToCheck
                  $null = (Remove-OldLogFiles -FuncFile $FileToCheck -FuncRetention $LGRetention -ErrorAction Stop)
               }
            }
         }
      }
   }

   # Start Service if needed
   if ($LGRestart -eq '1')
   {
      try
      {
         $msg = ('start service {0}' -f $LGService)
         Write-Verbose -Message $msg
         $null = (Start-Service -Name $LGService -ErrorAction Stop)
      }
      catch
      {
         $msg = ('could not start service {0}' -f $LGService)
         Write-Verbose -Message $msg
         Write-EventLog -LogName 'Application' -Source 'pslogrotate' -EntryType Error -EventId 2008 -Message $msg -ErrorAction Continue
      }
   }
}