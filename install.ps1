# install.ps1 — Install autonomous-ai-itagents skills (companion to autonomous-claude-skills)
# Remote install: irm https://raw.githubusercontent.com/fransanda/autonomous-ai-itagents/main/install.ps1 | iex
# Local install:  .\install.ps1 (from inside a cloned repo)

$ErrorActionPreference = "Stop"

$skillsDirs = @(
    "$env:USERPROFILE\.claude\skills",
    "$env:USERPROFILE\.agents\skills"
)

$tempClone = $null
if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot "skills\itagentsreview\SKILL.md"))) {
    $sourceRoot = $PSScriptRoot
} else {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Host "Error: git is required to install. Install git first." -ForegroundColor Red
        exit 1
    }
    $tempClone = Join-Path $env:TEMP "_acs_itagents_install_$(Get-Random)"
    Write-Host "Fetching itagents..." -ForegroundColor Cyan
    git clone --depth=1 --quiet https://github.com/fransanda/autonomous-ai-itagents.git $tempClone
    $sourceRoot = $tempClone
}

Write-Host ""
Write-Host "Installing autonomous-ai-itagents skills..." -ForegroundColor Cyan
Write-Host ""

$installed = @()
foreach ($skill in @("itagentsreview", "additagent")) {
    $source = Join-Path $sourceRoot "skills\$skill\SKILL.md"
    if (-not (Test-Path $source)) {
        Write-Host "  Source not found for /$skill — skipping" -ForegroundColor Yellow
        continue
    }
    foreach ($skillsDir in $skillsDirs) {
        $dest = "$skillsDir\$skill"
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        Copy-Item $source "$dest\SKILL.md" -Force
    }
    Write-Host "  Installed /$skill" -ForegroundColor Green
    $installed += $skill
}

# Install agent templates folder
$agentsSrc = Join-Path $sourceRoot "agents"
if (Test-Path $agentsSrc) {
    foreach ($skillsDir in $skillsDirs) {
        $tplDir = "$skillsDir\_itagents_templates\agents"
        New-Item -ItemType Directory -Path $tplDir -Force | Out-Null
        Copy-Item "$agentsSrc\*" $tplDir -Recurse -Force
    }
    Write-Host "  Installed agent templates" -ForegroundColor Green
}

if ($tempClone -and (Test-Path $tempClone)) {
    Remove-Item $tempClone -Recurse -Force
}

Write-Host ""
if ($installed.Count -eq 2) {
    Write-Host "Done! Restart Claude Code, then use:" -ForegroundColor Green
    Write-Host "  /itagentsreview          — run the multi-agent QA pipeline" -ForegroundColor White
    Write-Host "  /itagentsreview --full   — full codebase audit (review-only)" -ForegroundColor White
    Write-Host "  /additagent              — add a custom agent to the project" -ForegroundColor White
    Write-Host ""
    Write-Host "Note: requires autonomous-claude-skills installed first." -ForegroundColor Gray
    Write-Host ""
} else {
    Write-Host "Installation incomplete. Installed: $($installed -join ', ')" -ForegroundColor Yellow
}
