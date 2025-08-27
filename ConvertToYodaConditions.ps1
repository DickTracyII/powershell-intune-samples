# Convert Null Comparisons to Yoda Conditions
# This script modernizes null/empty comparisons to use Yoda conditions (constant on left side)

param(
    [Parameter(Mandatory = $false)]
    [switch]$WhatIf
)

Write-Host "Converting null comparisons to Yoda conditions..." -ForegroundColor Green

$totalFiles = 0
$totalChanges = 0
$filesToProcess = Get-ChildItem -Recurse -Filter "*.ps1" | Where-Object { 
    $_.Name -notlike "*Fix*" -and $_.Name -notlike "*Clean*" -and $_.Name -notlike "*Batch*" 
}

foreach ($file in $filesToProcess) {
    $content = Get-Content $file.FullName -Raw -Encoding UTF8
    $fileChanges = 0

    # Pattern 1: $null -eq $variable → $null -eq $variable
    $matches1 = [regex]::Matches($content, '(\$\w+)\s*(-eq)\s*(\$null)')
    if ($matches1.Count -gt 0) {
        $content = [regex]::Replace($content, '(\$\w+)\s*(-eq)\s*(\$null)', '$3 $2 $1')
        $fileChanges += $matches1.Count
    }

    # Pattern 2: $null -ne $variable → $null -ne $variable
    $matches2 = [regex]::Matches($content, '(\$\w+)\s*(-ne)\s*(\$null)')
    if ($matches2.Count -gt 0) {
        $content = [regex]::Replace($content, '(\$\w+)\s*(-ne)\s*(\$null)', '$3 $2 $1')
        $fileChanges += $matches2.Count
    }

    # Pattern 3: "" -eq $variable → "" -eq $variable
    $matches3 = [regex]::Matches($content, '(\$\w+)\s*(-eq)\s*("")')
    if ($matches3.Count -gt 0) {
        $content = [regex]::Replace($content, '(\$\w+)\s*(-eq)\s*("")', '$3 $2 $1')
        $fileChanges += $matches3.Count
    }

    # Pattern 4: "" -ne $variable → "" -ne $variable
    $matches4 = [regex]::Matches($content, '(\$\w+)\s*(-ne)\s*("")')
    if ($matches4.Count -gt 0) {
        $content = [regex]::Replace($content, '(\$\w+)\s*(-ne)\s*("")', '$3 $2 $1')
        $fileChanges += $matches4.Count
    }

    if ($fileChanges -gt 0) {
        if ($WhatIf) {
            Write-Host "✓ $($file.Name) - Would fix $fileChanges comparison(s)" -ForegroundColor Yellow
        } else {
            Set-Content -Path $file.FullName -Value $content -Encoding UTF8 -NoNewline
            Write-Host "✓ $($file.Name) - Fixed $fileChanges comparison(s)" -ForegroundColor Green
        }
        $totalFiles++
        $totalChanges += $fileChanges
    } else {
        Write-Host "• $($file.Name) - No changes needed" -ForegroundColor Gray
    }
}

Write-Host "`nYoda condition conversion complete!" -ForegroundColor Green
Write-Host "Files processed: $($filesToProcess.Count)" -ForegroundColor Cyan
Write-Host "Files changed: $totalFiles" -ForegroundColor Cyan
Write-Host "Total comparisons fixed: $totalChanges" -ForegroundColor Cyan

if ($WhatIf) {
    Write-Host "`nThis was a dry run. Run without -WhatIf to apply changes." -ForegroundColor Yellow
}
