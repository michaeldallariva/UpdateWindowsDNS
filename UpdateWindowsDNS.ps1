############################################################################################################################################################################################################################################################
# Update Windows DNS settings
# GitHub link : https://github.com/michaeldallariva
# Version : v1.0
# Author : Michael DALLA RIVA, with the help of some AI
# 27 Feb 2025
#
# Purpose:
# Useful when changing DNS servers in a corporate network for clients and servers not set to use DHCP.
# 
# To be deplolyed using your central PowerShell script solution such as SCCM etc
# 
# 1. Checks all network interfaces if they are set to DHCP - IF DHCP enabled : no change will occur
# 2. If a network interface is set to fixed IP, it will update the 2 DNS entries if they do not match the new DNS IP addresses variables below.
# 3. If a network interface is set to fixed IP but DNS entries are not populated (blank), it will not add the 2 DNS server's IP addresses below. This is useful for hosts with multiple network interfaces and/or in isolated VLAN/DMZ.
#
# License :
# Feel free to use for any purpose, personal or commercial.
#
############################################################################################################################################################################################################################################################

# Change the IP addresses of your own DNS servers below
$PrimaryDNS = "9.9.9.9"
$SecondaryDNS = "149.112.112.112"
$dnsServers = @($PrimaryDNS, $SecondaryDNS)

# Will be used to create a debug log file using the computer name. Check out its content to ensure the change was made as expected or if you are having troubles.
if (-not (Test-Path -Path "C:\temp")) {
    New-Item -Path "C:\temp" -ItemType Directory
}

$serverName = $env:COMPUTERNAME

$logFile = "C:\temp\${serverName}_dns.log"

function Log-Message {
    param (
        [string]$Message
    )
    Write-Output $Message
    Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message"
}

# Run the script with admin/system privileges
$isAdmin = [bool](([System.Security.Principal.WindowsIdentity]::GetCurrent()).groups -match 'S-1-5-32-544')
Log-Message "Starting DNS configuration script on $serverName"
Log-Message "Running as administrator: $isAdmin"
Log-Message "Windows version: $([System.Environment]::OSVersion.Version)"
Log-Message "Script configured to: ONLY modify interfaces with at least one existing DNS server (manual IP configuration)"

if (-not $isAdmin) {
    Log-Message "WARNING: This script requires administrator privileges to modify DNS settings. Please run PowerShell as Administrator."
}

try {

    $networkAdapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
    Log-Message "Found $($networkAdapters.Count) connected network adapters"
    
    foreach ($adapter in $networkAdapters) {
        $interfaceName = $adapter.Name
        $interfaceAlias = $adapter.InterfaceAlias
        $interfaceIndex = $adapter.ifIndex
        
        $currentDnsSettings = Get-DnsClientServerAddress -InterfaceIndex $interfaceIndex -AddressFamily IPv4
        $currentDnsServers = $currentDnsSettings.ServerAddresses
        
        Log-Message "Interface: $interfaceAlias (Index: $interfaceIndex)"
        Log-Message "Current DNS servers: $($currentDnsServers -join ', ')"
        
        try {
            $ipConfig = Get-NetIPConfiguration -InterfaceIndex $interfaceIndex -ErrorAction SilentlyContinue
            $isDhcp = $ipConfig.IPv4Address.PrefixOrigin -eq "Dhcp"
            Log-Message "Interface appears to be using DHCP: $isDhcp"
        }
        catch {
            Log-Message "Could not determine if interface is using DHCP: $($_.Exception.Message)"
            $isDhcp = "Unknown"
        }
        
        if ($null -eq $currentDnsServers -or $currentDnsServers.Count -eq 0) {
            Log-Message "DNS entries for interface $interfaceAlias are blank. Skipping this interface as requested."
            continue
        }
        elseif (@(Compare-Object $currentDnsServers $dnsServers -SyncWindow 0).Length -eq 0) {
            Log-Message "DNS settings for interface $interfaceAlias already match $($dnsServers -join ', '). No changes needed."
            continue
        }
        
        try {
            Log-Message "Attempting to set DNS for $interfaceAlias to $($dnsServers -join ', ')"
            Set-DnsClientServerAddress -InterfaceIndex $interfaceIndex -ServerAddresses $dnsServers -ErrorAction Stop
            Log-Message "DNS settings updated successfully using Set-DnsClientServerAddress"
        }
        catch {
            Log-Message "Error setting DNS with Set-DnsClientServerAddress: $($_.Exception.Message)"
            Log-Message "Trying alternative method (netsh)..."
            
            try {
                $netshCommand = "netsh interface ip set dns name=""$interfaceAlias"" static $PrimaryDNS primary"
                Log-Message "Executing: $netshCommand"
                $netshResult1 = Invoke-Expression $netshCommand
                Log-Message "Primary DNS result: $netshResult1"
                
                $netshCommand2 = "netsh interface ip add dns name=""$interfaceAlias"" $SecondaryDNS index=2"
                Log-Message "Executing: $netshCommand2"
                $netshResult2 = Invoke-Expression $netshCommand2
                Log-Message "Secondary DNS result: $netshResult2"
            }
            catch {
                Log-Message "Error setting DNS with netsh: $($_.Exception.Message)"
                Log-Message "Falling back to WMI method..."
                
                try {
                    $wmiAdapter = Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter "InterfaceIndex = '$interfaceIndex'"
                    if ($wmiAdapter) {
                        $result = $wmiAdapter.SetDNSServerSearchOrder($dnsServers)
                        if ($result.ReturnValue -eq 0) {
                            Log-Message "DNS settings updated successfully using WMI method"
                        }
                        else {
                            Log-Message "WMI method returned error code: $($result.ReturnValue)"
                        }
                    }
                    else {
                        Log-Message "Could not find WMI adapter with index $interfaceIndex"
                    }
                }
                catch {
                    Log-Message "Error using WMI method: $($_.Exception.Message)"
                }
            }
        }
    }
}
catch {
    Log-Message "Error in main processing: $($_.Exception.Message)"
}

# Pause for 10 seconds to allow changes to take effect
Log-Message "Waiting 10 seconds for changes to take effect..."
Start-Sleep -Seconds 10

Log-Message "Verifying DNS settings after changes:"
try {
    $updatedSettings = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | ForEach-Object {
        $dnsServers = (Get-DnsClientServerAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4).ServerAddresses
        [PSCustomObject]@{
            Interface = $_.Name
            Description = $_.InterfaceDescription
            Status = $_.Status
            DNSServers = $dnsServers -join ', '
        }
    }
    
    Log-Message "Final DNS configuration:"
    $updatedSettings | Format-Table -AutoSize
    
    Log-Message "===== DNS CONFIGURATION REPORT ====="
    Log-Message "Server Name: $serverName"
    Log-Message "Date: $(Get-Date)"
    Log-Message "-----------------------------------"
    
    foreach ($setting in $updatedSettings) {
        Log-Message "Interface: $($setting.Description)"
        Log-Message "Status: $($setting.Status)"
        Log-Message "DNS Servers: $($setting.DNSServers)"
        Log-Message "-----------------------------------"
    }
    
    Log-Message "DNS settings report completed"
    
    Log-Message "Final DNS configuration:"
    $updatedSettings | Format-Table -AutoSize
}
catch {
    Log-Message "Error verifying DNS settings: $($_.Exception.Message)"
}

Log-Message "Script completed"
