# DiagUi.ps1 - Diagnostic display helpers

function Print-DiagItem {
    param(
        [string]$Status,
        [string]$Label,
        [string]$Value
    )
    if ($Status -eq 'ok') {
        Write-Host -NoNewline '  [ ' -ForegroundColor White
        Write-Host -NoNewline 'OK' -ForegroundColor Green
        Write-Host -NoNewline ' ] ' -ForegroundColor White
    } elseif ($Status -eq 'warn') {
        Write-Host -NoNewline '  [' -ForegroundColor White
        Write-Host -NoNewline 'WARN' -ForegroundColor Yellow
        Write-Host -NoNewline '] ' -ForegroundColor White
    } else {
        Write-Host -NoNewline '  [' -ForegroundColor White
        Write-Host -NoNewline 'FAIL' -ForegroundColor Red
        Write-Host -NoNewline '] ' -ForegroundColor White
    }
    $paddedLabel = $Label.PadRight(45)
    Write-Host -NoNewline $paddedLabel
    Write-Host " : $Value"
}
