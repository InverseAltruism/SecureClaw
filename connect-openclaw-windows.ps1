param(
    [string]$VpsHost = "",
    [string]$SshUser = "",
    [int]$SshPort = 22,
    [int]$RemotePort = 0,
    [int]$LocalPort = 0,
    [string]$IdentityFile = "",
    [switch]$Foreground,
    [switch]$NoOpen,
    [switch]$NoDetect,
    [switch]$Yes
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptName = "secureclaw-connect-windows"
$DefaultGatewayPort = 18789
$PublicStateFile = "/etc/secureclaw-public.env"

function Info([string]$Message) {
    Write-Host "[$ScriptName] $Message"
}

function Warn([string]$Message) {
    Write-Warning "[$ScriptName] $Message"
}

function Die([string]$Message) {
    throw "[$ScriptName] $Message"
}

function Prompt-Text([string]$Label, [string]$DefaultValue = "") {
    if ([string]::IsNullOrWhiteSpace($DefaultValue)) {
        return (Read-Host "$Label")
    }
    $value = Read-Host "$Label [$DefaultValue]"
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $DefaultValue
    }
    return $value
}

function Prompt-YesNo([string]$Label, [bool]$DefaultYes = $true) {
    $defaultText = if ($DefaultYes) { "Y" } else { "N" }
    $reply = Read-Host "$Label [$defaultText]"
    if ([string]::IsNullOrWhiteSpace($reply)) {
        return $DefaultYes
    }
    return $reply -match "^[Yy]"
}

function Test-Port([int]$Port) {
    return $Port -ge 1 -and $Port -le 65535
}

function Wait-LocalTunnel([int]$Port, [int]$Retries = 10) {
    for ($i = 0; $i -lt $Retries; $i++) {
        try {
            if (Test-NetConnection -ComputerName "127.0.0.1" -Port $Port -InformationLevel Quiet -WarningAction SilentlyContinue) {
                return $true
            }
        } catch {
            Start-Sleep -Seconds 1
            continue
        }
        Start-Sleep -Seconds 1
    }
    return $false
}

function Detect-RemotePort {
    param(
        [string]$HostName,
        [string]$UserName,
        [int]$PortNumber,
        [string]$KeyPath
    )

    try {
        $sshArgs = @("-p", "$PortNumber", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8")
        if (-not [string]::IsNullOrWhiteSpace($KeyPath)) {
            $sshArgs += @("-i", $KeyPath)
        }
        $remoteCommand = "awk -F= '/^GATEWAY_PORT=/{print `$2; exit}' $PublicStateFile 2>/dev/null"
        $sshArgs += @("$UserName@$HostName", $remoteCommand)
        $detected = (& ssh @sshArgs 2>$null).Trim()
        if ($detected -match "^\d+$") {
            $value = [int]$detected
            if (Test-Port $value) {
                return $value
            }
        }
    } catch {
        return 0
    }
    return 0
}

if ([string]::IsNullOrWhiteSpace($VpsHost)) {
    $VpsHost = Prompt-Text "VPS host or IP"
}
if ([string]::IsNullOrWhiteSpace($SshUser)) {
    $SshUser = Prompt-Text "SSH username" "root"
}
if ($SshPort -eq 0) {
    $SshPort = [int](Prompt-Text "SSH port" "22")
}

if ([string]::IsNullOrWhiteSpace($IdentityFile)) {
    if (Prompt-YesNo "Use a custom SSH private key file?" $false) {
        $IdentityFile = Prompt-Text "SSH private key path" "$HOME\.ssh\id_ed25519"
    }
}

if ([string]::IsNullOrWhiteSpace($VpsHost)) { Die "VPS host is required." }
if ([string]::IsNullOrWhiteSpace($SshUser)) { Die "SSH user is required." }
if (-not (Test-Port $SshPort)) { Die "Invalid SSH port: $SshPort" }
if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) { Die "ssh.exe not found in PATH." }
if (-not [string]::IsNullOrWhiteSpace($IdentityFile) -and -not (Test-Path -Path $IdentityFile)) {
    Die "Identity file not found: $IdentityFile"
}

if ($RemotePort -eq 0) {
    if (-not $NoDetect) {
        $detectedPort = Detect-RemotePort -HostName $VpsHost -UserName $SshUser -PortNumber $SshPort -KeyPath $IdentityFile
        if ($detectedPort -gt 0) {
            $RemotePort = $detectedPort
            Info "Detected remote gateway port: $RemotePort"
        }
    }
    if ($RemotePort -eq 0) {
        Warn "Could not auto-detect remote gateway port."
        $RemotePort = [int](Prompt-Text "Remote OpenClaw gateway port" "$DefaultGatewayPort")
    }
}
if (-not (Test-Port $RemotePort)) { Die "Invalid remote port: $RemotePort" }

if ($LocalPort -eq 0) {
    $LocalPort = [int](Prompt-Text "Local browser port" "$RemotePort")
}
if (-not (Test-Port $LocalPort)) { Die "Invalid local port: $LocalPort" }

$dashboardUrl = "http://localhost:$LocalPort"

Info "Summary:"
Info "  SSH target : $SshUser@$VpsHost`:$SshPort"
Info "  Forwarding : localhost:$LocalPort -> 127.0.0.1:$RemotePort on VPS"
Info "  Dashboard  : $dashboardUrl"

if (-not $Yes) {
    if (-not (Prompt-YesNo "Start the tunnel now?" $true)) {
        Die "Cancelled."
    }
}

$sshTunnelArgs = @(
    "-p", "$SshPort",
    "-o", "ExitOnForwardFailure=yes",
    "-o", "ServerAliveInterval=30",
    "-o", "ServerAliveCountMax=3",
    "-N",
    "-L", "$LocalPort`:127.0.0.1:$RemotePort",
    "$SshUser@$VpsHost"
)
if (-not [string]::IsNullOrWhiteSpace($IdentityFile)) {
    $sshTunnelArgs = @("-i", $IdentityFile) + $sshTunnelArgs
}

Info "Starting SSH tunnel..."
if ($Foreground) {
    & ssh @sshTunnelArgs
} else {
    Start-Process -FilePath "ssh" -ArgumentList $sshTunnelArgs -WindowStyle Hidden | Out-Null
    if (-not (Wait-LocalTunnel -Port $LocalPort)) {
        Die "SSH process started but local tunnel port $LocalPort did not become reachable."
    }
    Info "Tunnel active. Open this URL: $dashboardUrl"
    if (-not $NoOpen) {
        Start-Process $dashboardUrl | Out-Null
    }
    Info "To close the tunnel later, stop the matching ssh.exe process."
}
