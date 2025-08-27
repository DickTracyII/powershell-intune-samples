# Fix Null Comparisons Script
# This script converts variable null/empty comparisons to Yoda conditions (constant on left side)
# Examples:
#   $variable -eq $null     →  $null -eq $variable
#   $variable -ne $null     →  $null -ne $variable  
#   $variable -eq ""        →  "" -eq $variable

param(
    [Parameter(Mandatory = $false)]
    [string[]]$ScriptPaths = @(),

    [Parameter(Mandatory = $false)]
    [string]$RootPath = "e:\Development\Github\Microsoft\powershell-intune-samples",

    [Parameter(Mandatory = $false)]
    [switch]$WhatIf,

    [Parameter(Mandatory = $false)]
    [switch]$Recursive,

    [Parameter(Mandatory = $false)]
    [string[]]$Include = @("*.ps1", "*.psm1", "*.psd1"),

    [Parameter(Mandatory = $false)]
    [string[]]$Exclude = @("*Helper*", "*Template*", "*Update*", "*Batch*", "*Clean*", "*Fix*")
)

function Repair-NullComparisons {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    try {
        $content = Get-Content -Path $FilePath -Raw -Encoding UTF8
        $originalContent = $content
        $changesCount = 0

        # Pattern 1: $variable -eq $null → $null -eq $variable
        $pattern1 = '(\$\w+)\s*(-eq)\s*(\$null)'
        $replacement1 = '$3 $2 $1'
        $matches1 = [regex]::Matches($content, $pattern1)
        if ($matches1.Count -gt 0) {
            $content = [regex]::Replace($content, $pattern1, $replacement1)
            $changesCount += $matches1.Count
        }

        # Pattern 2: $variable -ne $null → $null -ne $variable
        $pattern2 = '(\$\w+)\s*(-ne)\s*(\$null)'
        $replacement2 = '$3 $2 $1'
        $matches2 = [regex]::Matches($content, $pattern2)
        if ($matches2.Count -gt 0) {
            $content = [regex]::Replace($content, $pattern2, $replacement2)
            $changesCount += $matches2.Count
        }

        # Pattern 3: $variable -eq "" → "" -eq $variable
        $pattern3 = '(\$\w+)\s*(-eq)\s*("")'
        $replacement3 = '$3 $2 $1'
        $matches3 = [regex]::Matches($content, $pattern3)
        if ($matches3.Count -gt 0) {
            $content = [regex]::Replace($content, $pattern3, $replacement3)
            $changesCount += $matches3.Count
        }

        # Pattern 4: $variable -ne "" → "" -ne $variable
        $pattern4 = '(\$\w+)\s*(-ne)\s*("")'
        $replacement4 = '$3 $2 $1'
        $matches4 = [regex]::Matches($content, $pattern4)
        if ($matches4.Count -gt 0) {
            $content = [regex]::Replace($content, $pattern4, $replacement4)
            $changesCount += $matches4.Count
        }

        return @{
            ModifiedContent = $content
            OriginalContent = $originalContent
            ChangesCount = $changesCount
            HasChanges = ($changesCount -gt 0)
        }
    }
    catch {
        Write-Error "Error processing file $FilePath : $($_.Exception.Message)"
        return @{
            ModifiedContent = $null
            OriginalContent = $null
            ChangesCount = 0
            HasChanges = $false
            Error = $_.Exception.Message
        }
    }
}

# Main execution
Write-Host "Starting null comparison modernization..." -ForegroundColor Green

$filesToProcess = @()

if ($ScriptPaths.Count -gt 0) {
    $filesToProcess = $ScriptPaths
}
else {
    if ($Recursive) {
        $allFiles = Get-ChildItem -Path $RootPath -Recurse -Filter "*.ps1"
        $filesToProcess = $allFiles | Where-Object { 
            $file = $_
            $exclude = $false
            foreach ($pattern in $Exclude) {
                if ($file.Name -like $pattern) {
                    $exclude = $true
                    break
                }
            }
            return -not $exclude
        } | ForEach-Object { $_.FullName }
    }
    else {
        $allFiles = Get-ChildItem -Path $RootPath -Filter "*.ps1"
        $filesToProcess = $allFiles | Where-Object { 
            $file = $_
            $exclude = $false
            foreach ($pattern in $Exclude) {
                if ($file.Name -like $pattern) {
                    $exclude = $true
                    break
                }
            }
            return -not $exclude
        } | ForEach-Object { $_.FullName }
    }
}

Write-Host "`nFound $($filesToProcess.Count) files to process"

$totalFilesChanged = 0
$totalChanges = 0
$errorCount = 0

foreach ($filePath in $filesToProcess) {
    $fileName = Split-Path $filePath -Leaf
    
    $result = Repair-NullComparisons -FilePath $filePath
    
    if ($result.Error) {
        Write-Host "✗ $fileName - Error: $($result.Error)" -ForegroundColor Red
        $errorCount++
        continue
    }
    
    if ($result.HasChanges) {
        if ($WhatIf) {
            Write-Host "✓ $fileName - Would fix $($result.ChangesCount) null comparison(s)" -ForegroundColor Yellow
        }
        else {
            try {
                Set-Content -Path $filePath -Value $result.ModifiedContent -Encoding UTF8 -NoNewline
                Write-Host "✓ $fileName - Fixed $($result.ChangesCount) null comparison(s)" -ForegroundColor Green
            }
            catch {
                Write-Host "✗ $fileName - Failed to write changes: $($_.Exception.Message)" -ForegroundColor Red
                $errorCount++
                continue
            }
        }
        $totalFilesChanged++
        $totalChanges += $result.ChangesCount
    }
    else {
        Write-Host "• $fileName - No null comparisons found" -ForegroundColor Gray
    }
}

Write-Host "`nNull comparison modernization complete!" -ForegroundColor Green
Write-Host "Files processed: $($filesToProcess.Count)" -ForegroundColor Cyan
Write-Host "Files changed: $totalFilesChanged" -ForegroundColor Cyan
Write-Host "Total comparisons fixed: $totalChanges" -ForegroundColor Cyan
Write-Host "Errors: $errorCount" -ForegroundColor Cyan

if ($WhatIf) {
    Write-Host "`nThis was a dry run. Use without -WhatIf to apply changes." -ForegroundColor Yellow
}
