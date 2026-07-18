param(
    [string]$Distribution = "Ubuntu"
)

$ErrorActionPreference = "Stop"

Write-Host "Enabling Windows Subsystem for Linux..."
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart

Write-Host "Enabling Virtual Machine Platform..."
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart

Write-Host "Trying WSL distribution install: $Distribution"
wsl.exe --install -d $Distribution

Write-Host ""
Write-Host "WSL setup command finished. Restart Windows if prompted, then open Ubuntu and run:"
Write-Host "  cd /mnt/c/Users/kitamura.yoshiharu/Documents/td_change_monitor_codex_starter"
Write-Host "  curl -LsSf https://astral.sh/uv/install.sh | sh"
Write-Host '  export PATH="$HOME/.local/bin:$PATH"'
Write-Host "  bash scripts/verify.sh"
