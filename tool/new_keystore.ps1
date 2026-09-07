#Requires -Version 5.1
<#
.SYNOPSIS
    Creates the release signing keystore and the key.properties that points at
    it, so `flutter build appbundle --release` signs with your own key.

.DESCRIPTION
    Without android/key.properties the release build silently falls back to the
    debug keys (see android/app/build.gradle.kts), which Google Play will not
    accept. This script generates the keystore, writes the properties file, and
    prints the certificate fingerprints.

    THE KEYSTORE IS NOT RECOVERABLE. Unless you are enrolled in Play App
    Signing, losing it means you can never publish an update to an app already
    on the Play Store under the same listing -- you would have to publish a new
    one and leave your existing users behind. Back it up somewhere durable and
    off this machine before you ship anything signed with it.

    Neither the keystore nor key.properties is committed: .gitignore already
    excludes *.jks, *.keystore and android/key.properties.

.EXAMPLE
    .\tool\new_keystore.ps1
    Prompts for the password and writes android/keystore.jks.

.EXAMPLE
    .\tool\new_keystore.ps1 -OutFile 'D:\keys\dailyquran.jks' -ValidityYears 30
    Keeps the key off the repo drive entirely, which is the safer habit.

.EXAMPLE
    .\tool\new_keystore.ps1 -StoreType PKCS12
    Uses the modern standard format instead of the legacy JKS one.
#>
[CmdletBinding()]
param(
    # Where to write the keystore. Relative paths resolve against the repo root.
    [string] $OutFile = 'android/keystore.jks',

    # Name of the key inside the store. You need it again to sign, and it is
    # recorded in key.properties for you.
    [string] $Alias = 'dailyquran',

    # Play requires a key valid well past any update you intend to ship. 25
    # years is the usual advice and what Android Studio offers.
    [int] $ValidityYears = 27,

    # Goes into the certificate's subject. None of it is shown to users; it is
    # only ever read by tooling and by you.
    [string] $CommonName = 'Daily Quran',
    [string] $OrganizationalUnit = 'Daily Quran',
    [string] $Organization = 'i9tech',
    [string] $City = 'Unknown',
    [string] $State = 'Unknown',

    # Two-letter ISO country code.
    [ValidatePattern('^[A-Za-z]{2}$')]
    [string] $Country = 'BD',

    # JKS is what Flutter's own signing guide uses and what the .jks extension
    # means. PKCS12 is the current standard and equally acceptable to Gradle.
    [ValidateSet('JKS', 'PKCS12')]
    [string] $StoreType = 'JKS',

    [ValidateSet('RSA', 'EC')]
    [string] $KeyAlg = 'RSA',

    [int] $KeySize = 2048,

    # Skip writing android/key.properties, e.g. when adding a key to a store
    # the build already knows about.
    [switch] $NoKeyProperties,

    # Overwrite an existing keystore. Deliberately awkward: doing this to a key
    # you have already published with is unrecoverable.
    [switch] $Force
)

$ErrorActionPreference = 'Stop'

function Find-Keytool {
    # In the order most likely to be the JDK this project actually builds with.
    $onPath = Get-Command keytool -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }

    $candidates = @()
    if ($env:JAVA_HOME) { $candidates += (Join-Path $env:JAVA_HOME 'bin\keytool.exe') }

    # Flutter builds Android with Android Studio's bundled JDK unless told
    # otherwise, so that is the one whose keytool matches the build.
    $flutter = Get-Command flutter -ErrorAction SilentlyContinue
    if ($flutter) {
        $javaLine = (& flutter doctor -v 2>$null | Select-String -Pattern 'Java binary at:\s*(.+)$')
        if ($javaLine) {
            $javaPath = $javaLine.Matches[0].Groups[1].Value.Trim()
            $candidates += (Join-Path (Split-Path -Parent $javaPath) 'keytool.exe')
        }
    }

    $candidates += @(
        'C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe',
        'C:\Program Files\Android\Android Studio\jre\bin\keytool.exe',
        "$env:LOCALAPPDATA\Programs\Android Studio\jbr\bin\keytool.exe"
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return $candidate }
    }
    return $null
}

$repoRoot = Split-Path -Parent $PSScriptRoot

$keytool = Find-Keytool
if (-not $keytool) {
    throw @'
keytool was not found. It ships with any JDK. Either install Android Studio
(its bundled JDK is what Flutter builds Android with), or set JAVA_HOME to a
JDK you already have, then run this again.
'@
}
Write-Host "keytool: $keytool" -ForegroundColor DarkGray

# Resolve the output path before anything else, so the overwrite check and the
# path written into key.properties are talking about the same file.
if ([System.IO.Path]::IsPathRooted($OutFile)) {
    $keystorePath = [System.IO.Path]::GetFullPath($OutFile)
} else {
    $keystorePath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $OutFile))
}

if ((Test-Path -LiteralPath $keystorePath) -and -not $Force) {
    throw @"
A keystore already exists at:
  $keystorePath

Refusing to overwrite it. If it has ever signed a published release, replacing
it means you can no longer update that app. Pass -Force only if you are certain
this key has never been shipped.
"@
}

$parent = Split-Path -Parent $keystorePath
if ($parent -and -not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
}

# Read the password twice and compare, because a typo here is only discovered
# later, at the point where the keystore has become unopenable.
$first = Read-Host -Prompt 'Keystore password (at least 6 characters)' -AsSecureString
$second = Read-Host -Prompt 'Confirm password' -AsSecureString

$plainFirst = [Runtime.InteropServices.Marshal]::PtrToStringBSTR(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($first))
$plainSecond = [Runtime.InteropServices.Marshal]::PtrToStringBSTR(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($second))

try {
    if ($plainFirst -ne $plainSecond) { throw 'The passwords do not match. Nothing was written.' }
    if ($plainFirst.Length -lt 6) { throw 'keytool requires at least 6 characters. Nothing was written.' }

    $dname = "CN=$CommonName, OU=$OrganizationalUnit, O=$Organization, L=$City, ST=$State, C=$($Country.ToUpper())"

    # Passed through the environment rather than as arguments: command lines are
    # visible to any other process on the machine, and would land in your shell
    # history. The same password is used for the store and the key, which is
    # what Gradle and Android Studio both expect.
    $env:DQ_KEYSTORE_PASS = $plainFirst
    try {
        Write-Host "Creating $keystorePath ..." -ForegroundColor Cyan
        & $keytool -genkeypair `
            -alias $Alias `
            -keyalg $KeyAlg `
            -keysize $KeySize `
            -validity ([string]($ValidityYears * 365)) `
            -storetype $StoreType `
            -keystore $keystorePath `
            -dname $dname `
            -storepass:env DQ_KEYSTORE_PASS `
            -keypass:env DQ_KEYSTORE_PASS
        if ($LASTEXITCODE -ne 0) { throw "keytool exited with code $LASTEXITCODE." }

        if (-not $NoKeyProperties) {
            $propertiesPath = Join-Path $repoRoot 'android\key.properties'

            # Forward slashes on purpose: a .properties file treats a backslash
            # as an escape character, so a Windows path written raw would be
            # silently mangled. An absolute path also sidesteps the question of
            # what Gradle's file() resolves against.
            $storeFileValue = $keystorePath -replace '\\', '/'

            $contents = @"
# Release signing credentials. Generated by tool/new_keystore.ps1.
#
# NOT committed -- .gitignore excludes this file. Every machine that builds a
# release needs its own copy, pointing at a copy of the same keystore.
storeFile=$storeFileValue
storePassword=$plainFirst
keyAlias=$Alias
keyPassword=$plainFirst
"@
            Set-Content -Path $propertiesPath -Value $contents -Encoding utf8
            Write-Host "Wrote $propertiesPath" -ForegroundColor Green
        }

        Write-Host ''
        Write-Host 'Certificate fingerprints (Play Console, Firebase, Maps all ask for these):' -ForegroundColor Cyan
        & $keytool -list -v -alias $Alias -keystore $keystorePath -storepass:env DQ_KEYSTORE_PASS |
            Select-String -Pattern 'SHA1:|SHA256:|Valid from'
    } finally {
        Remove-Item Env:\DQ_KEYSTORE_PASS -ErrorAction SilentlyContinue
    }
} finally {
    # Do not leave the password sitting in the session's memory any longer than
    # the work needs it.
    $plainFirst = $null
    $plainSecond = $null
    [GC]::Collect()
}

Write-Host ''
Write-Host 'Done.' -ForegroundColor Green
Write-Host @"
Back up the keystore and its password somewhere off this machine, now.
Without them you cannot ship an update to a published app.

Build a signed release with:
  flutter build appbundle --release
"@ -ForegroundColor Yellow
