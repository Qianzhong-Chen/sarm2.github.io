# Compress all mp4 videos in current folder, except *_compressed.mp4.
# The compressed file will replace the original filename directly.

$TargetMaxMB = 45
$AudioKbps = 96
$MinVideoKbps = 500

$videos = Get-ChildItem -File -Filter "*.mp4" | Where-Object {
    $_.Name -notlike "*_compressed.mp4"
}

foreach ($video in $videos) {
    Write-Host "`nProcessing $($video.Name) ..." -ForegroundColor Cyan

    $input = $video.FullName
    $tmp = Join-Path $video.DirectoryName ("__tmp__" + $video.Name)

    $originalMB = [math]::Round($video.Length / 1MB, 2)

    # Get video duration in seconds
    $durationStr = ffprobe -v error -show_entries format=duration `
        -of default=noprint_wrappers=1:nokey=1 "$input"

    $duration = [double]$durationStr

    if ($duration -le 0) {
        Write-Host "Skip $($video.Name): cannot read duration." -ForegroundColor Yellow
        continue
    }

    if ($originalMB -gt $TargetMaxMB) {
        # Estimate video bitrate for target size.
        # Total size MB ~= (video_kbps + audio_kbps) * duration / 8192
        $totalKbps = ($TargetMaxMB * 8192) / $duration
        $videoKbps = [math]::Floor($totalKbps - $AudioKbps)

        if ($videoKbps -lt $MinVideoKbps) {
            $videoKbps = $MinVideoKbps
        }

        Write-Host "Original: $originalMB MB -> target: ~$TargetMaxMB MB, video bitrate: ${videoKbps}k"

        ffmpeg -y -i "$input" `
            -c:v libx264 -b:v "${videoKbps}k" `
            -maxrate "$([math]::Floor($videoKbps * 1.2))k" `
            -bufsize "$([math]::Floor($videoKbps * 2))k" `
            -preset slow `
            -c:a aac -b:a "${AudioKbps}k" `
            "$tmp"
    }
    else {
        # Mild compression for small videos.
        Write-Host "Original: $originalMB MB -> mild CRF compression"

        ffmpeg -y -i "$input" `
            -c:v libx264 -crf 23 -preset slow `
            -c:a aac -b:a "${AudioKbps}k" `
            "$tmp"
    }

    if (Test-Path $tmp) {
        $newSizeMB = [math]::Round((Get-Item $tmp).Length / 1MB, 2)

        if ($newSizeMB -lt $originalMB) {
            Move-Item -Force "$tmp" "$input"
            Write-Host "Replaced $($video.Name): $originalMB MB -> $newSizeMB MB" -ForegroundColor Green
        }
        else {
            Remove-Item "$tmp"
            Write-Host "Skipped replacement because compressed file is larger: $newSizeMB MB >= $originalMB MB" -ForegroundColor Yellow
        }
    }
}