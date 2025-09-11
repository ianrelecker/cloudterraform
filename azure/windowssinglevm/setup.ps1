<#
  Basic Windows setup script
  - Ensures RDP is enabled and firewall allows 3389
  - Optionally updates winget sources when available
  - Logs completion to Windows Event Log
#>

Write-Host "Starting Windows VM setup..."

# Enable script execution policy for current process
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# Ensure RDP is enabled at OS level
try {
    Write-Host "Enabling Remote Desktop (RDP)..."
    New-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -PropertyType DWord -Value 0 -Force | Out-Null
} catch {
    Write-Host "Failed to enable RDP registry setting: $($_.Exception.Message)"
}

# Ensure Windows Firewall allows RDP
try {
    Write-Host "Enabling Windows Firewall rule for RDP..."
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue | Out-Null
    # Fallback explicit rule (in case display group name differs)
    if (-not (Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object {$_.DisplayName -like '*Remote Desktop*' -and $_.Enabled -eq 'True'})) {
        New-NetFirewallRule -Name AllowRDP3389 -DisplayName "Allow RDP 3389" -Direction Inbound -Protocol TCP -LocalPort 3389 -Action Allow | Out-Null
    }
} catch {
    Write-Host "Failed to configure firewall for RDP: $($_.Exception.Message)"
}

# Update packages via winget if available (Server Core may not include it)
try {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "winget found, attempting package source update..."
        winget source update | Out-Null
        # Example: install useful tools if desired
        # winget install --silent Git.Git
    } else {
        Write-Host "winget not available; skipping winget operations."
    }
} catch {
    Write-Host "winget operations failed: $($_.Exception.Message)"
}

# Create a marker event to indicate completion
try {
    if (-not (Get-EventLog -LogName Application -Source "Windows Error Reporting" -ErrorAction SilentlyContinue)) {
        # 'Windows Error Reporting' usually exists; skip creating custom source
        Write-Host "Event source check complete."
    }
    Write-EventLog -LogName Application -Source "Windows Error Reporting" -EventId 1000 -EntryType Information -Message "VM setup completed via RunCommand"
} catch {
    Write-Host "Failed to write completion event: $($_.Exception.Message)"
}

Write-Host "Windows VM setup completed."
