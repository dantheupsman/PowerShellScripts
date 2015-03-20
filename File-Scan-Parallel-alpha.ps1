# Get all files sorted by size.

#Calculates the ORG Size totals after the file list is created.
Function global:Get-ORG-Totals 
{
Write-Host
Write-Host 'Generating ORG Totals '
$FileListVAR | 
Group ORG |
Select @{Name='ORGANIZATION'; Expression={$_.group.ORG[0]}}, @{Name='ORG_SIZE_MB';Expression={($_.group | Measure-Object -sum SIZEMB).sum}} |
Sort-Object { $_.ORG_SIZE_MB } -Descending | 
Export-Csv $ORG_List -force -NoTypeInformation 
#Invoke-Item $ORG_List
Write-Host
Write-Host 'ORG Totals have been generated and saved to ' $ORG_List -ForegroundColor Green
}

#Calculates the SITE Size totals after the file list is created.
Function global:Get-SITE-Totals 
{
Write-Host
Write-Host 'Generating Site Totals '
$FileListVAR | 
Group SITE |
Select @{Name='SITE'; Expression={$_.group.SITE[0]}}, @{Name='SITE_SIZE_MB';Expression={($_.group | Measure-Object -sum SIZEMB).sum}} |
Sort-Object { $_.SITE_SIZE_MB } -Descending | 
Export-Csv $SITE_List -force -NoTypeInformation 
#Invoke-Item $SITE_List
Write-Host
Write-Host 'Site Totals have been generated and saved to ' $Site_List -ForegroundColor Green
}

#Calculates the FILE_TYPE Size totals after the file list is created.
Function global:Get-FTYPE-Totals
{
Write-Host
Write-Host 'Generating File Type Totals '
$FileListVAR | 
Group FILETYPE |
Select @{Name='FILE_TYPE'; Expression={$_.group.FILETYPE[0]}}, @{Name='FTYPE_SIZE_MB';Expression={($_.group | Measure-Object -sum SIZEMB).sum}} |
Sort-Object { $_.FTYPE_SIZE_MB } -Descending | 
Export-Csv $FTYPE_List -force -NoTypeInformation 
#Invoke-Item $FTYPE_List
Write-Host
Write-Host 'File Type Totals have been generated and saved to ' $FTYPE_List -ForegroundColor Green
}

function IsNull($objectToCheck) {
    if (!$objectToCheck) {
        return $true
    }
 
    if ($objectToCheck -is [String] -and $objectToCheck -eq [String]::Empty) {
        return $true
    }
 
    if ($objectToCheck -is [DBNull] -or $objectToCheck -is [System.Management.Automation.Language.NullString]) {
        return $true
    }
 
    return $false
}


$GetORGTotals = {Get-ORG-Totals}
$GetSiteTotals = {Get-SITE-Totals}
$GetFTypeTotals = {Get-FTYPE-Totals}

$RootDirectory = Read-Host 'What is the directory to scan?'
$ResultsDirectory = Read-Host 'What directory would you like the results saved in?'
$MinFileSize = .01


$CurrentDate = (Get-Date -UFormat %Y-%m-%d) 
$FILE_List = $ResultsDirectory + $CurrentDate + '-' + 'FILE_List.csv'
$ORG_List = $ResultsDirectory + $CurrentDate + '-' + 'ORG_List.csv'
$SITE_List = $ResultsDirectory + $CurrentDate + '-' + 'SITE_List.csv'
$FTYPE_List = $ResultsDirectory + $CurrentDate + '-' + 'FTYPE_List.csv'
[REGEX]$ORG_REGEX = '\\[A-Za-z0-9]{6}-'
[REGEX]$SITE_REGEX = '\\[A-Za-z0-9]{6}-[A-Za-z0-9]{3}\\'
[REGEX]$LOGFolder_REGEX = 'Logs'
[REGEX]$DBFolder_REGEX = 'Databases'
[REGEX]$SW_Date_REGEX = '[0-9]{8}'
[REGEX]$CW_REGEX = '\\CW\\'
[REGEX]$TW_REGEX = '\\TW\\'
#[REGEX]$SW_Date_REGEX = '[0-9]{4}-[0-9]{2}-[0-9]{2}'

Write-Host
Write-Host 'Scanning the Directory supplied above: ' $RootDirectory

$FileListVAR = Get-ChildItem -Path $RootDirectory -Recurse -Force -File |
Select-Object -Property FullName,
    @{Name='SizeMB';Expression= {$_.Length / 1MB}},
    CreationTime,
    @{Name='SW_Date';Expression={$SW_Date_REGEX.Match($_.FullName)}},
    @{Name='ORG';Expression={$ORG_REGEX.Match($_.FullName)}},
    @{Name='SITE';Expression={$SITE_REGEX.Match($_.FullName)}},
    @{Name='LOGS_FOLDER';Expression={$_.FullName -match $LOGFolder_REGEX}},
    @{Name='FileType';Expression={$_.Extension}},
    @{Name='DB_FOLDER';Expression={$_.FullName -match $DBFolder_REGEX}} |
#    Where {$_.SizeMB -gt $MinFileSize}|
Where {$_.ORG.Length -gt 0} |
Where {($_.FullName -match $TW_REGEX) -or ($_.FullName -match $CW_REGEX) -ne $true} |
#Where {($_.FullName -match $CW_REGEX) -ne $true} |
Where {$_.Extension -ne '.tcj' -or '.jrn'} |
Sort-Object { $_.SizeMB } -Descending 

$FileListVAR | 
Export-CSV $FILE_List -force -NoTypeInformation 
#Invoke-Item $FILE_List 
Write-Host 'File List has been generated and saved to ' $FILE_List -ForegroundColor Green

#Calls the Export ORG Size Totals function.
Start-Job -ScriptBlock {Get-ORG-Totals} -InitializationScript $GetORGTotals -ArgumentList $FileListVAR $ORG_List

#Calls the Export SITE Size Totals function.
Start-Job -ScriptBlock {Get-SITE-Totals} -InitializationScript $GetSiteTotals -ArgumentList $FileListVAR 

#Calls the Export FTYPE Size Totals function.
Start-Job -ScriptBlock {Get-FTYPE-Totals} -InitializationScript $GetFTypeTotals -ArgumentList $FileListVAR 
Pause