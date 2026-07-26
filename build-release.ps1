<#
.SYNOPSIS
  Project Danubia client release/build script.

.DESCRIPTION
  1. Runs the client's built-in --encrypt step over data/modules/mods/layouts/init.lua
  2. Mirrors every included file (already encrypted) into wwwroot/client-updater/files/
     - this is what the AUTO-UPDATER downloads incrementally, one file at a time
  3. Computes CRC32 per file (must match libzip's file_stat.crc / stdext::dec_to_hex)
  4. Writes manifest.json (files + binary info) for the UpdaterController to serve
  5. Builds an initial data.zip and appends it to a copy of otclient.exe, for the
     ONE download link you put on the website (first-time installs, no server round trip)

.PARAMETER SourceDir
  Folder containing the raw, unencrypted client tree (data/, modules/, mods/, layouts/, init.lua)

.PARAMETER ExePath
  Path to the freshly built otclient.exe (same one that will run --encrypt)

.PARAMETER WwwRoot
  Path to the ASP.NET Core project's wwwroot folder

.PARAMETER EncryptSeed
  Seed string passed to `otclient.exe --encrypt <seed>` - keep this identical across
  builds unless you intentionally want to invalidate all previously encrypted files

.PARAMETER AppVersion
  Increment this and also bump APP_VERSION in init.lua before running --encrypt
#>

param(
    [Parameter(Mandatory = $true)][string]$SourceDir,
    [Parameter(Mandatory = $true)][string]$ExePath,
    [Parameter(Mandatory = $true)][string]$WwwRoot,
    [Parameter(Mandatory = $true)][string]$EncryptSeed,
    [Parameter(Mandatory = $true)][int]$AppVersion,
    [switch]$SkipEncrypt
)

$ErrorActionPreference = "Stop"

$includedDirs = @("data", "modules", "mods", "layouts", "things")
$includedRootFiles = @("init.lua")

$filesOut     = Join-Path $WwwRoot "client-updater/files"
$manifestOut  = Join-Path $WwwRoot "client-updater/manifest.json"
$initialZip   = Join-Path $env:TEMP "danubia-data.zip"
$exeName      = Split-Path $ExePath -Leaf
$exeDeployed  = Join-Path (Join-Path $WwwRoot "client-updater/files") $exeName

# --- CRC32 (must match stdext/libzip's CRC32) ---
Add-Type -TypeDefinition @"
using System;
public static class Crc32Helper {
    static uint[] table;
    static Crc32Helper() {
        table = new uint[256];
        const uint poly = 0xEDB88320;
        for (uint i = 0; i < 256; i++) {
            uint c = i;
            for (int k = 0; k < 8; k++)
                c = (c & 1) != 0 ? poly ^ (c >> 1) : c >> 1;
            table[i] = c;
        }
    }
    public static uint Compute(byte[] data) {
        uint crc = 0xFFFFFFFF;
        foreach (byte b in data)
            crc = table[(crc ^ b) & 0xFF] ^ (crc >> 8);
        return crc ^ 0xFFFFFFFF;
    }
}
"@

function Get-Crc32Hex($path) {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $crc = [Crc32Helper]::Compute($bytes)
    # verified against real client output: always 8 lowercase hex digits, zero-padded
    return $crc.ToString("x8")
}

Write-Host "== Project Danubia client release build ==" -ForegroundColor Cyan

# 1. Encrypt in place (skip if you already ran it manually / CI step)
if (-not $SkipEncrypt) {
    Write-Host "-- Running --encrypt in $SourceDir"
    Push-Location $SourceDir

    # IMPORTANT: otclient.exe --encrypt shows a blocking MessageBoxA("Success")
    # dialog after finishing, which nobody can click on a headless CI runner -
    # the process would hang forever waiting for it. So we don't wait for the
    # process to exit naturally; instead we watch stdout for the completion
    # line and kill the process ourselves once we see it.
    $stdOutFile = Join-Path $env:TEMP "encrypt-stdout.txt"
    if (Test-Path $stdOutFile) { Remove-Item $stdOutFile -Force }

    $proc = Start-Process -FilePath $ExePath -ArgumentList "--encrypt", $EncryptSeed `
        -RedirectStandardOutput $stdOutFile -NoNewWindow -PassThru

    $timeoutSeconds = 300
    $elapsed = 0
    $completed = $false
    while ($elapsed -lt $timeoutSeconds) {
        Start-Sleep -Seconds 2
        $elapsed += 2
        if ((Test-Path $stdOutFile) -and (Get-Content $stdOutFile -Raw -ErrorAction SilentlyContinue) -match "Encryption complete") {
            $completed = $true
            break
        }
        if ($proc.HasExited) {
            # exited on its own (e.g. no MessageBox on this environment) - fine either way
            $completed = $true
            break
        }
    }

    if (-not $proc.HasExited) {
        Write-Host "-- Encryption finished, closing lingering process/dialog" -ForegroundColor Yellow
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }

    if (-not $completed) {
        throw "otclient.exe --encrypt did not report completion within $timeoutSeconds seconds"
    }

    Pop-Location
} else {
    Write-Host "-- Skipping encrypt step (assumed already run)" -ForegroundColor Yellow
}

# 2. Collect the file list (post-encryption content)
$relativeFiles = @()
foreach ($dir in $includedDirs) {
    $full = Join-Path $SourceDir $dir
    if (Test-Path $full) {
        Get-ChildItem -Path $full -Recurse -File | ForEach-Object {
            $rel = $_.FullName.Substring($SourceDir.Length).TrimStart('\', '/').Replace('\', '/')
            $relativeFiles += $rel
        }
    }
}
foreach ($f in $includedRootFiles) {
    if (Test-Path (Join-Path $SourceDir $f)) {
        $relativeFiles += $f
    }
}

Write-Host "-- Found $($relativeFiles.Count) files to publish"

# 3. Mirror raw (encrypted) files into wwwroot/client-updater/files + build manifest
New-Item -ItemType Directory -Force -Path $filesOut | Out-Null
$manifestFiles = [ordered]@{}

foreach ($rel in $relativeFiles) {
    $src = Join-Path $SourceDir $rel
    $dst = Join-Path $filesOut $rel
    New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
    Copy-Item -Path $src -Destination $dst -Force

    $manifestFiles[$rel] = Get-Crc32Hex $src
}

# 4. Binary checksum (only meaningful if the exe itself changed this release)
$binaryChecksum = Get-Crc32Hex $ExePath
Copy-Item -Path $ExePath -Destination $exeDeployed -Force

# 5. Write manifest.json
$manifest = [ordered]@{
    files     = $manifestFiles
    binary    = @{ file = $exeName; checksum = $binaryChecksum }
    keepFiles = $false
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestOut -Encoding UTF8
Write-Host "-- Wrote manifest: $manifestOut ($($manifestFiles.Count) files)" -ForegroundColor Green

# 6. Build the INITIAL data.zip (for the one-time website download only)
#
# IMPORTANT: we do NOT use Compress-Archive here. It can emit "stored"
# (uncompressed) directory entries before the first real file, with a
# different "version needed to extract" byte than deflate-compressed files.
# The client's loadDataFromSelf() finds the embedded zip by scanning raw
# bytes for the exact signature PK\x03\x04 followed by version byte 0x14
# (deflate). If a directory entry comes first, the scan skips it and locks
# onto a LATER file's header instead - which is no longer the true start of
# the zip, so the central directory's offsets (which point relative to the
# real start) no longer line up, and mounting silently fails.
#
# Fix: build the zip ourselves via ZipArchive, adding ONLY real files
# (never explicit directory entries) with Deflate compression, so the very
# first entry is a proper 0x14-versioned file sitting at true offset 0.
if (Test-Path $initialZip) { Remove-Item $initialZip -Force }

Add-Type -AssemblyName System.IO.Compression

$zipFileStream = [System.IO.File]::Open($initialZip, 'Create')
$archive = New-Object System.IO.Compression.ZipArchive($zipFileStream, [System.IO.Compression.ZipArchiveMode]::Create)

try {
    foreach ($rel in $relativeFiles) {
        $src = Join-Path $SourceDir $rel
        # entry name must use forward slashes, no leading slash - same
        # convention PHYSFS/libzip use when reading entries back out
        $entryName = $rel.Replace('\', '/')
        $entry = $archive.CreateEntry($entryName, [System.IO.Compression.CompressionLevel]::Optimal)
        $entryStream = $entry.Open()
        $srcStream = [System.IO.File]::OpenRead($src)
        $srcStream.CopyTo($entryStream)
        $srcStream.Close()
        $entryStream.Close()
    }
} finally {
    $archive.Dispose()
    $zipFileStream.Close()
}

$initialExeOut = Join-Path $filesOut "..\ProjectDanubiaClient.exe" | Resolve-Path -ErrorAction SilentlyContinue
$websiteExePath = Join-Path (Join-Path $WwwRoot "client-updater") "ProjectDanubiaClient.exe"

# append data.zip bytes to a copy of the exe - loadDataFromSelf() finds the
# zip's local-file-header signature (PK..) by scanning, so a straight append works
Copy-Item -Path $ExePath -Destination $websiteExePath -Force
$exeStream = [System.IO.File]::Open($websiteExePath, 'Append')
$zipBytes = [System.IO.File]::ReadAllBytes($initialZip)
$exeStream.Write($zipBytes, 0, $zipBytes.Length)
$exeStream.Close()

Write-Host "-- Built website download (self-contained): $websiteExePath" -ForegroundColor Green

# 7. Zip the website download together with a short README (slightly lower
# browser download-warning level than a raw .exe, and gives us a place to
# explain the expected Windows SmartScreen warning to players)
$websiteZipPath = Join-Path (Join-Path $WwwRoot "client-updater") "ProjectDanubiaClient.zip"
$readmeTemp = Join-Path $env:TEMP "danubia-readme.txt"

@"
Project Danubia - Client

Halt dein schniessn
"@ | Set-Content -Path $readmeTemp -Encoding UTF8

if (Test-Path $websiteZipPath) { Remove-Item $websiteZipPath -Force }

$zipFileStream2 = [System.IO.File]::Open($websiteZipPath, 'Create')
$archive2 = New-Object System.IO.Compression.ZipArchive($zipFileStream2, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    $entry1 = $archive2.CreateEntry("ProjectDanubiaClient.exe", [System.IO.Compression.CompressionLevel]::Optimal)
    $s1 = $entry1.Open(); $src1 = [System.IO.File]::OpenRead($websiteExePath); $src1.CopyTo($s1); $src1.Close(); $s1.Close()

    $entry2 = $archive2.CreateEntry("README.txt", [System.IO.Compression.CompressionLevel]::Optimal)
    $s2 = $entry2.Open(); $src2 = [System.IO.File]::OpenRead($readmeTemp); $src2.CopyTo($s2); $src2.Close(); $s2.Close()
} finally {
    $archive2.Dispose()
    $zipFileStream2.Close()
}

Write-Host "-- Built website zip: $websiteZipPath" -ForegroundColor Green
Write-Host "== Done. Website download link should point at: /api/Updater/download (serving ProjectDanubiaClient.zip) ==" -ForegroundColor Cyan