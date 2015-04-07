
<#
.Synopsis
    This PowerShell script configures a device to use all the Embedded Lockdown
    settings defined from a configured machine.
.Description
    This script includes functions and settings exported from an existing
    system.
.Parameter ComputerName
    Optional parameter to specify the machine that this script should
    manage.  If not specified, the script will execute all changes
    locally.
.Example
    # update the current device
    <script name> 

    # update a computer
    <script name> -ComputerName kiosk1

    # update a list of computers
    <script name> -ComputerName (kiosk1,kiosk2,cashier1,cashier2)

    # update all the computers from names in a text file
    <script name> -ComputerName (Get-Content computerlist.txt)

    # update all the computers from a list of computers in Active Directory
    <script name> -ComputerName (Get-ADComputer -filter * | Select-Object -expand name)

    # update all the computers from CSV file with a host column
    <script name> -ComputerName (Import-CSV computerslist.csv | Select-Object -expand host)
#>

param
(
    [switch]$Elevated,
    [String]$ComputerName
)
   
$CommonArgs = @{"namespace"="root\standardcimv2\embedded"}
$CommonArgs += $PSBoundParameters



function IsAdministrator
{
    $Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object System.Security.Principal.WindowsPrincipal($Identity)
    $Principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}


function IsUacEnabled
{
    (Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System).EnableLua -ne 0
}

#
# Main script
#
if (!(IsAdministrator))
{
    if (IsUacEnabled)
    {
        [string[]]$argList = @('-NoProfile', '-NoExit', '-File', $MyInvocation.MyCommand.Path)
        $argList += $MyInvocation.BoundParameters.GetEnumerator() | Foreach {"-$($_.Key)", "$($_.Value)"}
        $argList += $MyInvocation.UnboundArguments
        Start-Process PowerShell.exe -Verb Runas -WorkingDirectory $pwd -ArgumentList $argList 
        return
    }
    else
    {
        throw "You must be administrator to run this script"
    }
}




function Set-WriteFilterDriver([Bool] $Enabled) {
    <#
    .Synopsis
        Enable or disable write filter driver
    .Description
        Enable or disable write filter driver.  If it is set to disabled (false),
        no more interactions may be made.  A reboot is required to apply this change.
    .Parameter Value
        Enabled = true, disabled = false
    #>

    $driverConfig = Get-WMIObject -class UWF_Filter @CommonArgs;

    if ($driverConfig) {
        if ($Enabled -eq $true) {
            $driverConfig.Enable() | Out-Null;
        } else {
            $driverConfig.Disable() | Out-Null;
        }
        Write-Host ("Set Write Filter Enabled to {0}" -f $Enabled)
    }
}

function Set-WriteFilterHORM([Bool] $Enabled) {
    <#
    .Synopsis
        Enable or disable write filter driver
    .Description
        Enable or disable write filter's HORM feature. To be enabled,
        all volumes must be protected, no write filter changes pending,
        and must have no file or registry exclusions. No reboot is required
        for this change to take place, but it must be hibernated to create
        the hibernation file that will be used in further reboots.
    .Parameter Value
        Enabled = true, disabled = false
    #>

    $driverConfig = Get-WMIObject -class UWF_Filter @CommonArgs;

    if ($driverConfig) {
        if ($Enabled -eq $true) {
            $driverConfig.EnableHORM() | Out-Null;
        } else {
            $driverConfig.DisableHORM() | Out-Null;
        }
        Write-Host ("Set Write Filter HORM Enabled to {0}" -f $Enabled)
    }
}

function Set-OverlayConfiguration([UInt32] $size, $overlayType) {
    <#
    .Synopsis
        Sets the overlay storage configuration
    .Description
        Sets the size of the storage medium
        that file and registry changes are redirected to.  Changes made
        to this require a reboot to take affect.
    .Parameter Value
        size - size in MB of the overlay size
    #>

    $nextConfig = Get-WMIObject -class UWF_OverlayConfig -Filter "CurrentSession = false" @CommonArgs;

    if ($nextConfig) {
        if ($overlayType -eq "Memory") {
            $nextConfig.SetType(0) | Out-Null;
            Write-Host "Set Maximum Overlay size to use Memory"
        }
        elseif ($overlayType -eq "Disk") {
            $nextConfig.SetType(1) | Out-Null;
            Write-Host "Set Maximum Overlay size to use Disk"
        }
        else {
            Write-Error ("{0} is not a valid overlay type, must be Disk or Memory" -f $overlayType);
            return;
        }
        
        $nextConfig.SetMaximumSize($size) | Out-Null;
        Write-Host ("Set Maximum Overlay size to {0}" -f $size)
    }
}

function Set-ProtectVolume($driveLetter, [bool] $enabled) {
    <#
    .Synopsis
        Enables or disables protection of a volume by drive letter
    .Description
        Enables or disables protection of a volume by drive letter.  Note that only
        volumes that have a drive letter are exported since the volumeName is unique
        to the computer. 
    .Parameter Value
        driveLetter - drive letter formatted as "C:"
        enabled - true = after reboot, all changes will be redirected to temporary space
    #>

    $nextConfig = Get-WMIObject -class UWF_Volume @CommonArgs |
        where {
            $_.DriveLetter -eq "$driveLetter" -and $_.CurrentSession -eq $false
        };

    if ($nextConfig) {

        if ($Enabled -eq $true) {
            $nextConfig.Protect() | Out-Null;
        } else {
            $nextConfig.Unprotect() | Out-Null;
        }
        Write-Host "Setting drive protection on $driveLetter to $enabled"
    }
    else {
        Set-WMIInstance -class UWF_Volume -argument @{CurrentSession=$false;DriveLetter="$driveLetter";Protected=$enabled } @CommonArgs | Out-Null
        Write-Host "Adding drive protection on $driveLetter and setting to $enabled"
    }
}

function Clear-FileExclusions($driveLetter) {
    <#
    .Synopsis
        Deletes all file exclusions for a drive
    .Description
        UWF cannot immediately delete a file exclusion but will mark them as deleted.
        Files that are marked as added however will be deleted as an undo.
    .Parameter Value
        driveLetter - drive letter formatted as "C:"
    #>

    $nextConfig = Get-WMIObject -class UWF_Volume @CommonArgs |
        where {
            $_.DriveLetter -eq "$driveLetter" -and $_.CurrentSession -eq $false
        };

    if ($nextConfig) {
        $nextConfig.RemoveAllExclusions() | Out-Null;
        Write-Host "Cleared all exclusions for $driveLetter";
    }
    else {
        Write-Error "Could not clear exclusions for unprotected drive $driveLetter";
    }
}

function Add-FileExclusion($driveLetter, $exclusion) {
    <#
    .Synopsis
        Adds a file exclusion entry a drive
    .Description
        Adds a single entry.  If the entry was marked as deleted, the delete
        flag will be cleared.  Otherwise, it will be marked as added. All changes are
        applied after reboot.
    .Parameter Value
        driveLetter - drive letter formatted as "C:"
        exclusion - a file or directory to exclude
    #>

    $nextConfig = Get-WMIObject -class UWF_Volume @CommonArgs |
        where {
            $_.DriveLetter -eq "$driveLetter" -and $_.CurrentSession -eq $false
        };

    if ($nextConfig) {
        $nextConfig.AddExclusion($exclusion) | Out-Null;
        Write-Host "Added exclusion $exclusion for $driveLetter";
    }
    else {
        Write-Error "Could not add exclusion for unprotected drive $driveLetter";
    }
}

function Clear-RegistryExclusions() {
    <#
    .Synopsis
        Deletes all registry exclusions 
    .Description
        UWF cannot immediately delete a registry exclusion but will mark them as deleted.
        Entries that are marked as added however will be deleted as an undo.
    #>

    $nextConfig = Get-WMIObject -class UWF_RegistryFilter @CommonArgs |
        where {
            $_.CurrentSession -eq $false;
        };
    if ($nextConfig) {
        $InArgs = $nextConfig.GetMethodParameters("GetExclusions")
        
        $outArgs = $nextConfig.InvokeMethod("GetExclusions", $InArgs, $Null)

        foreach($key in $outArgs.ExcludedKeys) {
            Write-Host "Clearing key $key.RegistryKey"
            $removeOutput = $nextConfig.RemoveExclusion($key.RegistryKey)
        }
    }
}

function Add-RegistryExclusion($exclusion) {
    <#
    .Synopsis
        Adds a registry exclusion entry a drive
    .Description
        Adds a single entry.  If the entry was marked as deleted, the delete
        flag will be cleared.  Otherwise, it will be marked as added. All changes are
        applied after reboot.
    .Parameter Value
        exclusion - a file or directory to exclude
    #>

    $nextConfig = Get-WMIObject -class UWF_RegistryFilter @CommonArgs |
        where {
            $_.CurrentSession -eq $false;
        };

    if ($nextConfig) {
        $nextConfig.AddExclusion($exclusion) | Out-Null;
        Write-Host "Added exclusion $exclusion";
    }
    else {
        Write-Error "Could not add exclusion for unprotected drive $driveLetter";
    }
}


New-ItemProperty -Path HKLM:\SOFTWARE\DSI\UWFSwitch -Name Servicing -PropertyType DWord -Value 1 -Force
New-ItemProperty -Path HKLM:\SOFTWARE\Wow6432Node\DSI\UWFSwitch -Name Servicing -PropertyType DWord -Value 1 -Force

Set-WriteFilterDriver $False
Start-Sleep -Seconds 1
Restart-Computer -Force