<#
  Windows 11 initial setup script
  - Enables Remote Desktop (RDP)
  - Ensures Windows Firewall allows TCP/3389
  - Updates winget sources if available
  - Logs completion
#>

Write-Host "Starting Windows 11 VM setup..."

Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# Enable RDP (Desktop)
try {
    Write-Host "Enabling Remote Desktop (RDP)..."
    New-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -PropertyType DWord -Value 0 -Force | Out-Null
} catch {
    Write-Host "Failed to enable RDP registry setting: $($_.Exception.Message)"
}

# Windows Firewall: allow RDP
try {
    Write-Host "Enabling Windows Firewall rule for RDP..."
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue | Out-Null
    if (-not (Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object {$_.DisplayName -like '*Remote Desktop*' -and $_.Enabled -eq 'True'})) {
        New-NetFirewallRule -Name AllowRDP3389 -DisplayName "Allow RDP 3389" -Direction Inbound -Protocol TCP -LocalPort 3389 -Action Allow | Out-Null
    }
} catch {
    Write-Host "Failed to configure firewall for RDP: $($_.Exception.Message)"
}

# winget source update (optional)
try {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "winget found, attempting package source update..."
        winget source update | Out-Null
    } else {
        Write-Host "winget not available; skipping winget operations."
    }
} catch {
    Write-Host "winget operations failed: $($_.Exception.Message)"
}

# Completion event
try {
    Write-EventLog -LogName Application -Source "Windows Error Reporting" -EventId 1000 -EntryType Information -Message "Windows 11 VM setup completed via RunCommand"
} catch {
    Write-Host "Failed to write completion event: $($_.Exception.Message)"
}

Write-Host "Windows 11 VM setup completed."

