# Alias for 7-zip
if (-not (test-path "$env:ProgramFiles\7-Zip\7z.exe")) {throw "$env:ProgramFiles\7-Zip\7z.exe needed"}
set-alias sz "$env:ProgramFiles\7-Zip\7z.exe"
 
$path = Read-Host 'What is the root that you would like to zip up?'
 
foreach($dir in gci -Path $path | where{$_.PSIsContainer})
{
    $zipFile = $path + '\' + $dir.Name + ".7z"
    sz a -m0=lzma2 -mx=9 -aoa -md=128m -mmt=4 "$zipfile" $dir.FullName
    Remove-Item $dir.FullName -Recurse -Force
}
