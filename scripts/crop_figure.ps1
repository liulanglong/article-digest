param(
  [Parameter(Mandatory = $true)][string]$Image,
  [Parameter(Mandatory = $true)][int]$X1,
  [Parameter(Mandatory = $true)][int]$Y1,
  [Parameter(Mandatory = $true)][int]$X2,
  [Parameter(Mandatory = $true)][int]$Y2,
  [Parameter(Mandatory = $true)][string]$Out
)
# 鎸夊潗鏍囦粠鍘熷浘瑁佸壀鍥捐〃鍖哄煙锛岃緭鍑?PNG
Add-Type -AssemblyName System.Drawing
if (-not (Test-Path $Image)) { Write-Output "ERR: file not found: $Image"; exit 1 }
$w = $X2 - $X1; $h = $Y2 - $Y1
if ($w -le 0 -or $h -le 0) { Write-Output "ERR: invalid rect"; exit 1 }
$src = [System.Drawing.Image]::FromFile($Image)
$bmp = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$dst = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
$srcRect = New-Object System.Drawing.Rectangle($X1, $Y1, $w, $h)
$g.DrawImage($src, $dst, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
$g.Dispose()
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose(); $src.Dispose()
Write-Output "saved: $Out (${w}x${h})"
