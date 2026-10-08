param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Target,
    [ValidateSet('pdf', 'pptx')][string]$Format = 'pdf'
)
# Saves a copy of a presentation with PowerPoint, in the background (no window): as a PDF (hidden
# slides included, so slide n is page n) or as a .pptx (to read the notes and comments of an old
# .ppt, which is not a zip of XML files). An open PowerPoint is used as it is and left running; one
# started here is closed again.
$ErrorActionPreference = 'Stop'
$app = $null
$presentation = $null
$startedHere = $false
try {
    try {
        $app = [Runtime.InteropServices.Marshal]::GetActiveObject('PowerPoint.Application')
    } catch {
        $app = New-Object -ComObject PowerPoint.Application
        $startedHere = $true
    }
    # ReadOnly, not Untitled, WithWindow = false
    $presentation = $app.Presentations.Open($Source, -1, 0, 0)
    # Hidden slides are skipped by an export, so show them all: only in memory (the file is open
    # read-only and never saved), and slide n is then page n of the PDF.
    if ($Format -eq 'pdf') {
        foreach ($slide in $presentation.Slides) { $slide.SlideShowTransition.Hidden = 0 }
        $presentation.SaveCopyAs($Target, 32)   # 32 = PDF
    } else {
        $presentation.SaveCopyAs($Target, 24)   # 24 = PowerPoint presentation (.pptx)
    }
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 2
} finally {
    if ($presentation) { try { $presentation.Saved = -1; $presentation.Close() } catch {} }
    if ($startedHere -and $app) {
        try { if ($app.Presentations.Count -eq 0) { $app.Quit() } } catch {}
    }
}
