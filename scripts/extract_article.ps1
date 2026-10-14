param(
  [Parameter(Mandatory = $true)][string]$Image,
  [int]$SegmentHeight = 2600,
  [string]$OutDir = ""
)
# 闀挎埅鍥?-> 鍒囧垎 -> Windows 涓枃 OCR -> 鍏ㄦ枃鏂囨湰 + 閫愯鍧愭爣
# 杈撳嚭: %TEMP%\article_ocr.txt (鍏ㄦ枃) / %TEMP%\article_pos.txt (SEG娈靛彿|y1|y2|x1|x2|鏂囨湰)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Runtime.WindowsRuntime

$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await($WinRtTask, $ResultType) {
  $asTask = $asTaskGeneric.MakeGenericMethod($ResultType)
  $netTask = $asTask.Invoke($null, @($WinRtTask))
  $netTask.Wait(-1) | Out-Null
  $netTask.Result
}

[Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null
[Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null
[Windows.Graphics.Imaging.SoftwareBitmap, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null
[Windows.Storage.StorageFile, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null

if (-not (Test-Path $Image)) { Write-Output "ERR: file not found: $Image"; exit 1 }
if ($OutDir -eq "") { $OutDir = Join-Path $env:TEMP "article_ocr_segs" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$src = [System.Drawing.Image]::FromFile($Image)
$w = $src.Width; $h = $src.Height
$n = [int][Math]::Ceiling($h / $SegmentHeight)
Write-Output "image: ${w}x${h}, segments: $n"

$codecs = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders()
$jpegCodec = $null
for ($j = 0; $j -lt $codecs.Length; $j++) { if ($codecs[$j].MimeType -eq "image/jpeg") { $jpegCodec = $codecs[$j] } }
$eps = New-Object System.Drawing.Imaging.EncoderParameters(1)
$eps.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]82)

for ($i = 0; $i -lt $n; $i++) {
  $y = $i * $SegmentHeight
  $ch = [int][Math]::Min($SegmentHeight, $h - $y)
  $bmp = New-Object System.Drawing.Bitmap($w, $ch)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $dst = New-Object System.Drawing.Rectangle(0, 0, $w, $ch)
  $srcRect = New-Object System.Drawing.Rectangle(0, $y, $w, $ch)
  $g.DrawImage($src, $dst, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
  $g.Dispose()
  $bmp.Save((Join-Path $OutDir "artseg_$i.jpg"), $jpegCodec, $eps)
  $bmp.Dispose()
}
$src.Dispose()

$langs = [Windows.Media.Ocr.OcrEngine]::AvailableRecognizerLanguages
$zh = $langs | Where-Object { $_.LanguageTag -like "zh*" } | Select-Object -First 1
if ($zh) { $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($zh) }
else { $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages() }
if (-not $engine) { Write-Output "ERR: no OCR engine available"; exit 1 }

$textBuilder = New-Object System.Text.StringBuilder
$posBuilder = New-Object System.Text.StringBuilder

for ($i = 0; $i -lt $n; $i++) {
  $p = Join-Path $OutDir "artseg_$i.jpg"
  $file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($p)) ([Windows.Storage.StorageFile])
  $stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
  $decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
  $bmp = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
  $bmp = [Windows.Graphics.Imaging.SoftwareBitmap]::Convert($bmp, [Windows.Graphics.Imaging.BitmapPixelFormat]::Bgra8, [Windows.Graphics.Imaging.BitmapAlphaMode]::Premultiplied)
  $res = Await ($engine.RecognizeAsync($bmp)) ([Windows.Media.Ocr.OcrResult])
  $off = $i * $SegmentHeight
  [void]$textBuilder.AppendLine("===== SEG $i =====")
  [void]$textBuilder.AppendLine($res.Text)
  foreach ($line in $res.Lines) {
    $x1 = 99999; $y1 = 999999; $x2 = 0; $y2 = 0
    foreach ($wd in $line.Words) {
      $r = $wd.BoundingRect
      if ($r.X -lt $x1) { $x1 = $r.X }
      if ($r.Y -lt $y1) { $y1 = $r.Y }
      if (($r.X + $r.Width) -gt $x2) { $x2 = $r.X + $r.Width }
      if (($r.Y + $r.Height) -gt $y2) { $y2 = $r.Y + $r.Height }
    }
    [void]$posBuilder.AppendLine("SEG$i|$($off + $y1)|$($off + $y2)|$x1|$x2|$($line.Text)")
  }
  $bmp.Dispose(); $stream.Dispose()
}

$textOut = Join-Path $env:TEMP "article_ocr.txt"
$posOut = Join-Path $env:TEMP "article_pos.txt"
[System.IO.File]::WriteAllText($textOut, $textBuilder.ToString(), [System.Text.Encoding]::UTF8)
[System.IO.File]::WriteAllText($posOut, $posBuilder.ToString(), [System.Text.Encoding]::UTF8)
Write-Output "OCR done."
Write-Output "text: $textOut"
Write-Output "positions: $posOut"
