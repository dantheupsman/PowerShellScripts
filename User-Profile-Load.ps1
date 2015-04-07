# users stored in csv with "username, password" format
$userlist = 'c:\windows\Temp\Userlist.csv'


#$Usernames = (import-csv $userlist).Username
#$Passwords = (Import-csv $userlist).Password

$Logins = Import-csv $userlist


$Logins |
ForEach-Object {
    $spw = ConvertTo-SecureString $_.Password -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential -ArgumentList $_.Username,$spw
    Start-Process cmd \c -WindowStyle hidden -Credential $cred -ErrorAction SilentlyContinue -LoadUserProfile
}

Remove-Item $userlist