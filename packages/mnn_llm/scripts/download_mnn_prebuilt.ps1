# Download MNN prebuilt libraries (LLM-enabled) for Android arm64-v8a.
#
# Windows PowerShell equivalent of download_mnn_prebuilt.sh.
#
# Downloads:
#   1. Prebuilt Android .so files (libMNN.so, libllm.so, libMNN_Express.so, …)
#      from MNN 3.6.1 GitHub Release
#   2. Source archive (MNN-3.6.1.tar.gz) for headers:
#        include/MNN/*.hpp
#        3rd_party/imageHelper/stb_image.h
#        transformers/llm/engine/include/llm/*.hpp
#
# Output layout:
#   third_party/mnn/android/arm64-v8a/
#       include/ ...
#       libMNN.so  libllm.so  libMNN_Express.so  …

$ErrorActionPreference = "Stop"

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$PluginRoot  = Resolve-Path (Join-Path $ScriptDir "..")
$MnnRoot       = Join-Path $PluginRoot "third_party\mnn"
$AndroidRoot   = Join-Path $MnnRoot "android\arm64-v8a"
$MnnTag        = "3.6.1"
$DownloadDir   = Join-Path $MnnRoot "_download"

# ---- 0. Create directories ----
New-Item -ItemType Directory -Force -Path (Join-Path $AndroidRoot "include") | Out-Null
New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null

Write-Host ("==> Target directory: " + $AndroidRoot)

# ---- 1. Prebuilt .so files ----
$PrebuiltZip   = "mnn_" + $MnnTag + "_android_armv7_armv8_cpu_opencl_vulkan.zip"
$PrebuiltUrl   = "https://github.com/alibaba/MNN/releases/download/" + $MnnTag + "/" + $PrebuiltZip
$PrebuiltZipPath = Join-Path $DownloadDir $PrebuiltZip
$LibMnnPath   = Join-Path $AndroidRoot "libMNN.so"

if (-not (Test-Path $LibMnnPath)) {
    Write-Host ("==> Downloading prebuilt Android libraries (" + $MnnTag + ")")
    Write-Host ("    From: " + $PrebuiltUrl)
    if (Test-Path $PrebuiltZipPath) {
        Write-Host "    (zip already downloaded, reusing)"
    } else {
        try {
            $ProgressPreference = "SilentlyContinue"
            Invoke-WebRequest -Uri $PrebuiltUrl -OutFile $PrebuiltZipPath -UseBasicParsing
        } catch {
            Write-Error ("Failed to download prebuilt zip: " + $_.Exception.Message)
            exit 1
        }
    }

    $ExtractRoot = Join-Path $DownloadDir "prebuilt"
    if (Test-Path $ExtractRoot) { Remove-Item -Recurse -Force $ExtractRoot }
    New-Item -ItemType Directory -Force -Path $ExtractRoot | Out-Null

    Write-Host "    Extracting..."
    try {
        Expand-Archive -Path $PrebuiltZipPath -DestinationPath $ExtractRoot -Force
    } catch {
        Write-Error ("Failed to extract zip: " + $_.Exception.Message)
        exit 1
    }

    $Arm64Dirs = Get-ChildItem -Recurse -Directory $ExtractRoot |
        Where-Object { $_.Name -eq "arm64-v8a" }
    if (-not $Arm64Dirs) {
        Write-Error "No arm64-v8a directory found inside the extracted zip."
        Write-Host ("  Listing " + $ExtractRoot)
        Get-ChildItem -Recurse $ExtractRoot | Select-Object -First 30 FullName
        exit 1
    }
    foreach ($Arm64Dir in $Arm64Dirs) {
        $SoFiles = Get-ChildItem -File (Join-Path $Arm64Dir.FullName "*.so")
        if ($SoFiles) {
            Write-Host ("    Copying " + $SoFiles.Count + " .so files from " + $Arm64Dir.FullName)
            Copy-Item -Force $SoFiles.FullName -Destination $AndroidRoot
        }
    }
} else {
    Write-Host "    (libMNN.so already present, skipping prebuilt download)"
}

# ---- 2. Headers from source archive ----
$LlmHppPath = Join-Path $AndroidRoot "include\transformers\llm\engine\include\llm\llm.hpp"

if (-not (Test-Path $LlmHppPath)) {
    Write-Host ("==> Downloading MNN source archive for headers (" + $MnnTag + ")")
    $SrcTarGz = "MNN-" + $MnnTag + ".tar.gz"
    $SrcUrl   = "https://github.com/alibaba/MNN/archive/refs/tags/" + $MnnTag + ".tar.gz"
    $SrcTarGzPath = Join-Path $DownloadDir $SrcTarGz
    if (Test-Path $SrcTarGzPath) {
        Write-Host "    (source archive already downloaded, reusing)"
    } else {
        try {
            $ProgressPreference = "SilentlyContinue"
            Invoke-WebRequest -Uri $SrcUrl -OutFile $SrcTarGzPath -UseBasicParsing
        } catch {
            Write-Error ("Failed to download source archive: " + $_.Exception.Message)
            exit 1
        }
    }

    Write-Host "    Extracting tar.gz ..."
    $SrcExtractDir = Join-Path $DownloadDir ("MNN-" + $MnnTag)
    if (Test-Path $SrcExtractDir) { Remove-Item -Recurse -Force $SrcExtractDir }
    $TarExe = Get-Command tar -ErrorAction SilentlyContinue
    if ($TarExe) {
        & tar -xzf $SrcTarGzPath -C $DownloadDir
        if ($LASTEXITCODE -ne 0) {
            Write-Error ("tar extraction failed with exit code " + $LASTEXITCODE)
            exit 1
        }
    } else {
        Write-Host "    tar not in PATH; extracting with .NET classes ..."
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $TarStream = [System.IO.File]::OpenRead($SrcTarGzPath)
        try {
            $Gzip = New-Object System.IO.Compression.GzipStream($TarStream, [System.IO.Compression.CompressionMode]::Decompress)
            try {
                $MemStream = New-Object System.IO.MemoryStream
                $Gzip.CopyTo($MemStream)
                $MemStream.Position = 0
                $TarArchive = New-Object System.IO.Compression.TarArchive($MemStream, [System.IO.Compression.ZipArchiveMode]::Read, $false)
                foreach ($entry in $TarArchive.Entries) {
                    $Dest = Join-Path $DownloadDir $entry.FullName
                    $DestDir = Split-Path -Parent $Dest
                    if (-not (Test-Path $DestDir)) {
                        New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
                    }
                    if ($entry.Length -gt 0) {
                        $entry.ExtractToFile($Dest, $true)
                    }
                }
            } finally {
                $Gzip.Dispose()
            }
        } finally {
            $TarStream.Dispose()
        }
    }

    if (-not (Test-Path $SrcExtractDir)) {
        Write-Error ("Expected source dir not found after extraction: " + $SrcExtractDir)
        exit 1
    }

    # 2a. MNN core headers (include/MNN/*.hpp)
    $SrcInclude = Join-Path $SrcExtractDir "include"
    $DstInclude = Join-Path $AndroidRoot "include"
    if (Test-Path $SrcInclude) {
        Write-Host "    Copying include/ ..."
        Copy-Item -Recurse -Force (Join-Path $SrcInclude "*") -Destination $DstInclude
    } else {
        Write-Warning ("    Source include/ not found at: " + $SrcInclude)
    }

    # 2b. 3rd_party headers (stb_image lives under 3rd_party/imageHelper)
    $SrcThirdParty = Join-Path $SrcExtractDir "3rd_party"
    $DstThirdParty = Join-Path $DstInclude "3rd_party"
    if (Test-Path $SrcThirdParty) {
        if (-not (Test-Path $DstThirdParty)) {
            New-Item -ItemType Directory -Force -Path $DstThirdParty | Out-Null
        }
        Write-Host "    Copying 3rd_party/ ..."
        Copy-Item -Recurse -Force (Join-Path $SrcThirdParty "*") -Destination $DstThirdParty
    } else {
        Write-Warning "    Source 3rd_party/ not found"
    }

    # 2c. LLM engine headers (transformers/llm/engine/include/llm/*.hpp)
    $SrcLlmInclude = Join-Path $SrcExtractDir "transformers\llm\engine\include"
    $DstLlmRoot = Join-Path $DstInclude "transformers\llm\engine\include"
    if (Test-Path $SrcLlmInclude) {
        if (-not (Test-Path $DstLlmRoot)) {
            New-Item -ItemType Directory -Force -Path $DstLlmRoot | Out-Null
        }
        Write-Host "    Copying llm engine include/ ..."
        Copy-Item -Recurse -Force (Join-Path $SrcLlmInclude "*") -Destination $DstLlmRoot
    } else {
        Write-Warning ("    Source llm include/ not found at: " + $SrcLlmInclude)
    }

    # 2d. Copy transformers/llm source headers (llm_config.hpp etc)
    $SrcLlmHeadersDir = Join-Path $SrcExtractDir "transformers\llm"
    $DstLlmHeadersRoot = Join-Path $DstInclude "transformers\llm\engine\include"
    if (Test-Path $SrcLlmHeadersDir) {
        $TopHpp = Get-ChildItem -File (Join-Path $SrcLlmHeadersDir "*.hpp") -ErrorAction SilentlyContinue
        if ($TopHpp) {
            $DstLlmIncludeDir = Join-Path $DstLlmHeadersRoot "llm"
            if (-not (Test-Path $DstLlmIncludeDir)) {
                New-Item -ItemType Directory -Force -Path $DstLlmIncludeDir | Out-Null
            }
            Copy-Item -Force $TopHpp.FullName -Destination $DstLlmIncludeDir
        }
    }
} else {
    Write-Host "    (llm.hpp already present, skipping source download)"
}

# ---- 3. Cleanup ----
if (Test-Path $DownloadDir) {
    Write-Host ("==> Cleaning up " + $DownloadDir)
    Remove-Item -Recurse -Force $DownloadDir
}

# ---- 4. Verify output ----
Write-Host ""
Write-Host ("==> Done. Libraries and headers installed at " + $AndroidRoot)
$SoFiles = Get-ChildItem -File (Join-Path $AndroidRoot "*.so")
$SoList = $SoFiles | ForEach-Object Name
Write-Host ("    .so files: " + ($SoList -join ", "))
if (Test-Path $LlmHppPath) {
    Write-Host ("    llm.hpp   : OK (" + $LlmHppPath + ")")
} else {
    $m = "llm.hpp: MISSING at " + $LlmHppPath
    Write-Warning $m
}
