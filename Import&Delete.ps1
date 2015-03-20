$USERTYPE1 = ([Environment]::UserDomainName + "\" + [Environment]::UserName) 
$USERTYPE2 = "$env:userdomain\$env:username" 
$USERTYPE3 = [Security.Principal.WindowsIdentity]::GetCurrent().Name 
$CurrentTime = Get-Date

if ($USERTYPE1 -eq $USERTYPE2 -and $USERTYPE2 -eq $USERTYPE3)
{
$USER = $USERTYPE1
}

$UserLog = New-Object PSObject
$UserLog | Add-Member User $USER
$UserLog | Add-Member Time $CurrentTime
$UserLog | Export-Csv -Append -force -NoTypeInformation  Deletion-Log\Delete-Log.csv


Write-Host 'Use of this script is logged, as it can have unwanted consequences if you delete the wrong file.' -ForegroundColor Green


$CSVSource = Read-Host 'What is the file that you would like to import?'

Import-Csv -Path $CSVSource

