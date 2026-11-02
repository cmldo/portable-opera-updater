#Requires -Version 5.1
<#
.SYNOPSIS
  Portable Opera Updater - versione PowerShell (GUI WinForms).
.DESCRIPTION
  Scarica gli installer Opera (GX / Developer / Beta / Stable, x86 / x64), li estrae con
  Bin\7zr.exe e li installa in modalita' portable, con lo stesso formato su disco della versione C#
  (<cartella>\updates\Version.log = versione|ring|arch).
  Gestisce la pagina di avviso Zscaler (HTTP 403): apre il link nel browser, tu clicchi "Continua",
  poi si riprova. Verifica dimensione e SHA256 forniti dall'API di Opera.
  Crea/aggiorna da solo i launcher "<cartella> Launcher.exe" (compilati al volo con csc.exe di .NET Framework).
  Autoaggiornamento da GitHub (se $SelfUpdateBase e' impostato): confronta Opera-Updater.version e verifica SHA256.
  Log: OperaUpdater.log accanto allo script.
.PARAMETER UpdateAll
  Modalita' console: aggiorna tutto cio' che e' gia' installato ed esce (come "-UpdateAll" della versione C#).
.PARAMETER NoSelfUpdate
  Salta il controllo di aggiornamento dello script.
#>
[CmdletBinding()]
param([switch]$UpdateAll, [switch]$NoSelfUpdate)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$Root     = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$WorkDir  = Join-Path $Root 'Update'
$LogFile  = Join-Path $Root 'OperaUpdater.log'
$BrowserUA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36 OPR/115.0.0.0'
$SingleDir = 'Opera'

$ScriptVersion   = '1.2.0'
# Cartella "raw" su GitHub con Opera-Updater.ps1 e Opera-Updater.version.
# Nel repo viene riscritta in automatico dalla GitHub Action (.github/workflows/release-meta.yml).
# Vuoto o con "YOUR_USER" = autoaggiornamento disattivato.
$SelfUpdateBase  = 'https://raw.githubusercontent.com/YOUR_USER/portable-opera-updater/main'
$LauncherVersion = '2.0.0.0'

# Sorgente del launcher (C# 5, compilato con csc.exe). Segnaposto: __TITLE__ __LVER__ __INSTDIR__
$LauncherSource = @'
using System;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;

[assembly: AssemblyTitle("__TITLE__")]
[assembly: AssemblyProduct("Portable Opera Launcher")]
[assembly: AssemblyVersion("__LVER__")]
[assembly: AssemblyFileVersion("__LVER__")]

static class Program
{
    const string InstDir = "__INSTDIR__";
    const string Title = "__TITLE__";

    [STAThread]
    static int Main(string[] args)
    {
        string app = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\');
        string dir = Path.Combine(app, InstDir);
        string exe = Path.Combine(dir, "opera.exe");
        string prof = Path.Combine(dir, "Profile.txt");
        string lang = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName;

        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);

        if (!File.Exists(exe))
        {
            string msg = "Opera is not installed";
            if (lang == "it") msg = "Opera non e' installato";
            else if (lang == "de") msg = "Opera ist nicht installiert";
            else if (lang == "ru") msg = "Opera Portable \u043d\u0435 \u043d\u0430\u0439\u0434\u0435\u043d";
            MessageBox.Show(msg, Title, MessageBoxButtons.OK, MessageBoxIcon.Exclamation);
            return 1;
        }

        if (!File.Exists(prof))
        {
            using (ProfileForm f = new ProfileForm(lang, prof, InstDir)) { f.ShowDialog(); }
            if (!File.Exists(prof)) return 0; // finestra chiusa senza scegliere
        }

        // Profile.txt = argomenti grezzi; --user-data-dir relativo viene risolto rispetto alla cartella del launcher
        string raw = File.ReadAllText(prof).Trim();
        raw = Regex.Replace(raw, "--user-data-dir=(?:\"([^\"]*)\"|(\\S+))", delegate (Match m)
        {
            string v = m.Groups[1].Success ? m.Groups[1].Value : m.Groups[2].Value;
            if (!Path.IsPathRooted(v)) v = Path.Combine(app, v);
            return "\"--user-data-dir=" + v + "\"";
        });

        StringBuilder sb = new StringBuilder(raw);
        foreach (string a in args) { sb.Append(' ').Append(Quote(a)); }
        Process.Start(exe, sb.ToString().Trim());
        return 0;
    }

    static string Quote(string a)
    {
        if (a.Length > 0 && a.IndexOfAny(new char[] { ' ', '\t', '"' }) < 0) return a;
        int bs = 0;
        StringBuilder r = new StringBuilder("\"");
        foreach (char c in a)
        {
            if (c == '\\') { bs++; continue; }
            if (c == '"') { r.Append('\\', bs * 2 + 1).Append('"'); bs = 0; continue; }
            r.Append('\\', bs).Append(c); bs = 0;
        }
        r.Append('\\', bs * 2).Append('"');
        return r.ToString();
    }
}

class ProfileForm : Form
{
    readonly string profPath;
    readonly string instDir;
    RadioButton rbAll, rbSep, rbStd;

    public ProfileForm(string lang, string profPath, string instDir)
    {
        this.profPath = profPath;
        this.instDir = instDir;
        string tAll = "Use one profile for all versions";
        string tSep = "Use a separate profile for each version";
        string tStd = "Use the standard profile of Opera";
        if (lang == "it")
        {
            tAll = "Usa un solo profilo per tutte le versioni";
            tSep = "Usa un profilo separato per ogni versione";
            tStd = "Usa il profilo standard di Opera";
        }
        else if (lang == "de")
        {
            tAll = "Ein Profil f\u00fcr alle Versionen verwenden";
            tSep = "F\u00fcr jede Version ein eigenes Profil verwenden";
            tStd = "Das Standard Profil von Opera verwenden";
        }
        else if (lang == "ru")
        {
            tAll = "\u0418\u0441\u043f\u043e\u043b\u044c\u0437\u043e\u0432\u0430\u0442\u044c \u043e\u0434\u0438\u043d \u043f\u0440\u043e\u0444\u0438\u043b\u044c \u0434\u043b\u044f \u0432\u0441\u0435\u0445 \u0432\u0435\u0440\u0441\u0438\u0439";
            tSep = "\u0418\u0441\u043f\u043e\u043b\u044c\u0437\u043e\u0432\u0430\u0442\u044c \u0440\u0430\u0437\u043d\u044b\u0435 \u043f\u0430\u043f\u043a\u0438 \u0434\u043b\u044f \u043f\u0440\u043e\u0444\u0438\u043b\u0435\u0439 \u0440\u0430\u0437\u043d\u044b\u0445 \u0432\u0435\u0440\u0441\u0438\u0439";
            tStd = "\u0418\u0441\u043f\u043e\u043b\u044c\u0437\u043e\u0432\u0430\u0442\u044c \u0441\u0442\u0430\u043d\u0434\u0430\u0440\u0442\u043d\u043e\u0435 \u043c\u0435\u0441\u0442\u043e\u0440\u0430\u0441\u043f\u043e\u043b\u043e\u0436\u0435\u043d\u0438\u0435 \u043f\u0440\u043e\u0444\u0438\u043b\u044f";
        }

        Text = instDir + " Launcher";
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false; MinimizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(420, 150);

        rbAll = new RadioButton(); rbAll.Text = tAll; rbAll.AutoSize = true; rbAll.Location = new Point(16, 16);
        rbSep = new RadioButton(); rbSep.Text = tSep; rbSep.AutoSize = true; rbSep.Location = new Point(16, 44); rbSep.Checked = true;
        rbStd = new RadioButton(); rbStd.Text = tStd; rbStd.AutoSize = true; rbStd.Location = new Point(16, 72);
        Button ok = new Button(); ok.Text = "OK"; ok.Size = new Size(90, 28); ok.Location = new Point(314, 108);
        ok.Click += OkClick;
        AcceptButton = ok;
        Controls.Add(rbAll); Controls.Add(rbSep); Controls.Add(rbStd); Controls.Add(ok);
    }

    void OkClick(object sender, EventArgs e)
    {
        string content = "";
        if (rbAll.Checked) content = "--user-data-dir=\"profile\"";
        else if (rbSep.Checked) content = "--user-data-dir=\"" + instDir + "\\profile\"";
        File.WriteAllText(profPath, content);
        Close();
    }
}
'@

# --- Tabella delle 8 varianti (stesso ordine della versione C#) -------------------------------
$Rings = @(
    @{ Ring='Opera GX';  Arch='x86'; Path='v4/netinstaller/gx/Stable/windows/i386'; Dir='Opera GX x86'    },
    @{ Ring='Developer'; Arch='x86'; Path='v2/netinstaller/Developer/windows/i386'; Dir='Opera Dev x86'   },
    @{ Ring='Beta';      Arch='x86'; Path='v2/netinstaller/Beta/windows/i386';      Dir='Opera Beta x86'  },
    @{ Ring='Stable';    Arch='x86'; Path='v2/netinstaller/Stable/windows/i386';    Dir='Opera Stable x86'},
    @{ Ring='Opera GX';  Arch='x64'; Path='v4/netinstaller/gx/Stable/windows/x64';  Dir='Opera GX x64'    },
    @{ Ring='Developer'; Arch='x64'; Path='v2/netinstaller/Developer/windows/x64';  Dir='Opera Dev x64'   },
    @{ Ring='Beta';      Arch='x64'; Path='v2/netinstaller/Beta/windows/x64';       Dir='Opera Beta x64'  },
    @{ Ring='Stable';    Arch='x64'; Path='v2/netinstaller/Stable/windows/x64';     Dir='Opera Stable x64'}
)
$RowNames = @('Opera GX', 'Developer', 'Beta', 'Stable')

# --- Testi -------------------------------------------------------------------------------------
$lang = [Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName
if ($lang -eq 'it') {
    $T = @{
        Title='Portable Opera Updater'; LabelAll='Installa tutte le versioni x86 / x64'
        InstallAll='Installa tutto'; UpdateAll='Aggiorna tutto'; Exit='Esci'
        Sep='Cartella separata per ogni versione'; IgnoreVer='Ignora controllo versione'
        Shortcut='Crea collegamento sul desktop'; Ready='Pronto'
        Checking='Controllo versioni ({0}/8)...'; Download='Download {0}'
        Unpack='Estrazione in corso...'; Install='Installazione...'; Done='Completato: {0}'
        UpToDate='Questa versione e'' gia'' installata.'
        Running='Opera e'' in esecuzione: chiudilo prima di aggiornare.'
        ZBlock = "Il download di {0} e' stato bloccato (403), probabilmente dalla pagina di avviso di Zscaler.`n`nHo aperto il link nel browser: clicca 'Continua' (poi puoi annullare il download del browser) e premi Riprova."
        ErrTitle='Errore'; NoRemote="Nessuna versione remota disponibile.`nControlla connessione/proxy (vedi log)."
        Aborted='Operazione annullata.'
        SelfUpd='Nuova versione dello script disponibile: {0} (attuale {1}).`nAggiornare ora?'
    }
} else {
    $T = @{
        Title='Portable Opera Updater'; LabelAll='Install all x86 / x64 versions'
        InstallAll='Install all'; UpdateAll='Update all'; Exit='Exit'
        Sep='Separate folder for each version'; IgnoreVer='Ignore version check'
        Shortcut='Create desktop shortcut'; Ready='Ready'
        Checking='Checking versions ({0}/8)...'; Download='Downloading {0}'
        Unpack='Unpacking...'; Install='Installing...'; Done='Done: {0}'
        UpToDate='This version is already installed.'
        Running='Opera is running: close it before updating.'
        ZBlock = "The download of {0} was blocked (403), most likely by the Zscaler warning page.`n`nI opened the link in your browser: click 'Continue' (you can then cancel the browser download) and press Retry."
        ErrTitle='Error'; NoRemote="No remote version available.`nCheck connection/proxy (see log)."
        Aborted='Operation cancelled.'
        SelfUpd='A new script version is available: {0} (current {1}).`nUpdate now?'
    }
}

# --- Stato condiviso ---------------------------------------------------------------------------
$script:Console = [bool]$UpdateAll
$script:Busy    = $false
$script:Abort   = $false
$script:Remote  = New-Object object[] 8
$script:Opt     = @{ Separate = $false; IgnoreVer = $false; Shortcut = $false }
$script:DlTitle = ''
$script:LastStatus = ''

function Write-Log([string]$m) {
    try { Add-Content -LiteralPath $LogFile -Value ('{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $m) -Encoding UTF8 } catch {}
}
function Pump { if (-not $script:Console) { [System.Windows.Forms.Application]::DoEvents() } }

function Set-Status([string]$text, [int]$pct = 0, [string]$right = '') {
    if ($script:Console) {
        if ($text -ne $script:LastStatus) { Write-Host $text; $script:LastStatus = $text }
        if ($pct -gt 0) { Write-Progress -Activity $T.Title -Status "$text $right" -PercentComplete $pct } else { Write-Progress -Activity $T.Title -Completed }
        return
    }
    $script:lblStatus.Text = $text
    $script:lblRight.Text  = $right
    $script:bar.Value      = [Math]::Max(0, [Math]::Min(100, $pct))
    Pump
}

function Show-Error([string]$msg) {
    Write-Log "ERRORE: $msg"
    if ($script:Console) { Write-Host "ERRORE: $msg" -ForegroundColor Red; return }
    [void][System.Windows.Forms.MessageBox]::Show("$msg`n`nLog: $LogFile", $T.ErrTitle, 'OK', 'Error')
}

# --- Helper installazioni locali ---------------------------------------------------------------
function Get-InstDir([int]$i) { if ($script:Opt.Separate) { $Rings[$i].Dir } else { $SingleDir } }

function Read-VersionLog([string]$dir) {
    $log = Join-Path $dir 'updates\Version.log'
    if (-not (Test-Path -LiteralPath $log)) { return $null }
    $p = (Get-Content -LiteralPath $log -Raw).Trim().Split('|')
    if ($p.Count -lt 3) { return $null }
    [pscustomobject]@{ Version = $p[0]; Ring = $p[1]; Arch = $p[2] }
}

# Installazione locale corrispondente alla variante $i (in modalita' cartella unica solo se ring+arch coincidono)
function Get-LocalFor([int]$i) {
    $l = Read-VersionLog (Join-Path $Root (Get-InstDir $i))
    if ($l -and $l.Ring -eq $Rings[$i].Ring -and $l.Arch -eq $Rings[$i].Arch) { return $l }
    $null
}

function Test-Outdated([int]$i) {
    $l = Get-LocalFor $i; $r = $script:Remote[$i]
    if (-not $l -or -not $r) { return $false }
    try { return ([version]$r.Version -gt [version]$l.Version) } catch { return ($r.Version -ne $l.Version) }
}

# --- API Opera ---------------------------------------------------------------------------------
function Get-RemoteInfo([int]$i) {
    $ts   = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $json = '{"country":"DE","http_referrer":"https://www.opera.com/","installer_name":"OperaSetup.exe","product":{"name":"opera"},"query":"/opera/stable/windows?utm_tryagain=yes","system":{"platform":{"arch":"x86_64","opsys":"Windows","opsys-version":"10","package":"EXE"}},"timestamp":"' + $ts + '","uuid":"11111111-1111-1111-1111-111111111111"}'
    $body = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(('1' * 64) + ':' + $json))
    $r = Invoke-WebRequest -UseBasicParsing -Method Post -Uri ('https://autoupdate.geo.opera.com/' + $Rings[$i].Path) -Body $body -TimeoutSec 30
    $j = $r.Content | ConvertFrom-Json
    $m = [regex]::Match([string]$j.installer_filename, '\d+(\.\d+){3}')
    if (-not $m.Success -or -not $j.installer) { throw "Risposta API inattesa: $($r.Content)" }
    [pscustomobject]@{ Version = $m.Value; Url = [string]$j.installer; Size = [long]$j.installer_size; Sha256 = [string]$j.installer_checksum }
}

function Refresh-Remote {
    $ok = 0
    for ($i = 0; $i -lt 8; $i++) {
        $script:Remote[$i] = $null
        if ($Rings[$i].Arch -eq 'x64' -and -not [Environment]::Is64BitOperatingSystem) { continue }
        Set-Status ($T.Checking -f ($i + 1)) (($i + 1) * 12)
        try   { $script:Remote[$i] = Get-RemoteInfo $i; $ok++; Write-Log ("API {0} {1}: {2}" -f $Rings[$i].Ring, $Rings[$i].Arch, $script:Remote[$i].Version) }
        catch { Write-Log ("API {0} {1} FALLITA: {2}" -f $Rings[$i].Ring, $Rings[$i].Arch, $_.Exception.Message) }
    }
    Set-Status $T.Ready 0
    if ($ok -eq 0) { Show-Error $T.NoRemote }
}

# --- Download (con gestione Zscaler) -----------------------------------------------------------
function Save-Download([string]$Url, [string]$Dest, [scriptblock]$OnProgress) {
    $resp = $null
    try {
        $req = [Net.HttpWebRequest]::Create($Url)
        $req.UserAgent = $BrowserUA
        $req.Timeout = 30000; $req.ReadWriteTimeout = 30000
        $req.Proxy = [Net.WebRequest]::GetSystemWebProxy()
        $req.Proxy.Credentials = [Net.CredentialCache]::DefaultCredentials
        $resp = $req.GetResponse()
        if ($resp.ContentType -like 'text/html*') { return @{ Ok = $false; Status = 403; Message = 'Risposta HTML (pagina di blocco?)' } }
        $total = $resp.ContentLength
        $in  = $resp.GetResponseStream()
        $out = [IO.File]::Create($Dest)
        try {
            $buf = New-Object byte[] 262144
            $done = [long]0
            $sw = [Diagnostics.Stopwatch]::StartNew(); $last = 0
            while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
                if ($script:Abort) { throw 'Annullato' }
                $out.Write($buf, 0, $n); $done += $n
                if ($sw.ElapsedMilliseconds - $last -ge 120) { $last = $sw.ElapsedMilliseconds; & $OnProgress $done $total }
            }
            & $OnProgress $done $total
        } finally { $out.Dispose() }
        return @{ Ok = $true; Status = 200; Message = '' }
    }
    catch [Net.WebException] {
        $st = 0; if ($_.Exception.Response) { $st = [int]$_.Exception.Response.StatusCode }
        Remove-Item -LiteralPath $Dest -Force -ErrorAction SilentlyContinue
        return @{ Ok = $false; Status = $st; Message = $_.Exception.Message }
    }
    catch {
        Remove-Item -LiteralPath $Dest -Force -ErrorAction SilentlyContinue
        return @{ Ok = $false; Status = 0; Message = $_.Exception.Message }
    }
    finally { if ($resp) { $resp.Close() } }
}

function Request-Unlock([string]$Url, [string]$Name) {
    Write-Log "403 su $Name -> richiesto sblocco Zscaler nel browser"
    try { Start-Process $Url } catch { Write-Log "Start-Process fallito: $($_.Exception.Message)" }
    if ($script:Console) {
        Write-Host ($T.ZBlock -f $Name) -ForegroundColor Yellow
        $a = Read-Host 'Premi Invio per riprovare (q per annullare)'
        return ($a -ne 'q')
    }
    $res = [System.Windows.Forms.MessageBox]::Show(($T.ZBlock -f $Name), $T.Title, 'RetryCancel', 'Warning')
    return ($res -eq 'Retry')
}

function Set-DownloadStatus($done, $total) {
    $pct = if ($total -gt 0) { [int](100 * $done / $total) } else { 0 }
    Set-Status ($T.Download -f $script:DlTitle) $pct ('{0:N1} / {1:N1} MB' -f ($done / 1MB), ($total / 1MB))
}

function Get-Installer([int]$i, [string]$Dest) {
    $r = $script:Remote[$i]
    $res = $null
    for ($try = 1; $try -le 5; $try++) {
        $res = Save-Download -Url $r.Url -Dest $Dest -OnProgress { param($d, $t) Set-DownloadStatus $d $t }
        if ($res.Ok) { break }
        if ($script:Abort) { throw $T.Aborted }
        if ($res.Status -eq 403) {
            if (Request-Unlock $r.Url (Split-Path $Dest -Leaf)) { continue }
            throw $T.Aborted
        }
        throw ('Download fallito: ' + $res.Message)
    }
    if (-not $res.Ok) { throw ('Download fallito dopo vari tentativi: ' + $res.Message) }

    $len = (Get-Item -LiteralPath $Dest).Length
    if ($len -eq 0 -or ($r.Size -gt 0 -and $len -ne $r.Size)) { throw "Dimensione inattesa del file scaricato ($len byte, attesi $($r.Size))." }
    if ($r.Sha256) {
        $h = (Get-FileHash -LiteralPath $Dest -Algorithm SHA256).Hash
        if ($h -ne $r.Sha256) { throw 'Checksum SHA256 non valido: file corrotto o alterato.' }
    }
    Write-Log "Download OK: $Dest ($len byte, SHA256 verificato)"
}

# --- Estrazione e installazione ----------------------------------------------------------------
function Get-7z {
    $c = @((Join-Path $Root 'Bin\7zr.exe'), (Join-Path $Root 'Bin\7z.exe'),
           "$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe")
    foreach ($p in $c) { if ($p -and (Test-Path -LiteralPath $p)) { return $p } }
    throw "7zr.exe non trovato: mettilo in '$(Join-Path $Root 'Bin')'."
}

function Install-Ring([int]$i, [bool]$Force = $false) {
    $d = $Rings[$i]; $r = $script:Remote[$i]
    if (-not $r) { throw "Versione remota non disponibile per $($d.Ring) $($d.Arch)." }
    $instName = Get-InstDir $i
    $target   = Join-Path $Root $instName

    $loc = Get-LocalFor $i
    if ($loc -and $loc.Version -eq $r.Version -and -not $Force) { Write-Log "$instName gia' aggiornata ($($loc.Version))"; return 'uptodate' }

    New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
    $safe = ('{0}_{1}_{2}' -f $r.Version, $d.Ring, $d.Arch) -replace '\s', '_'
    $dl   = Join-Path $WorkDir ("Opera_$safe.exe")
    $ext  = Join-Path $WorkDir $instName
    Remove-Item -LiteralPath $ext -Recurse -Force -ErrorAction SilentlyContinue

    try {
        $script:DlTitle = "Opera $($d.Ring) $($r.Version) $($d.Arch)"
        Write-Log "=== Installazione $script:DlTitle in '$target'"
        Get-Installer $i $dl

        Set-Status $T.Unpack 100
        $z = Get-7z
        $proc = Start-Process -FilePath $z -ArgumentList ('x "{0}" -o"{1}" -y' -f $dl, $ext) -PassThru -WindowStyle Hidden
        $null = $proc.Handle
        while (-not $proc.HasExited) { Pump; Start-Sleep -Milliseconds 80 }
        Write-Log "7z exit code: $($proc.ExitCode)"
        if ($proc.ExitCode -gt 1) { throw "Estrazione fallita (7z exit code $($proc.ExitCode))." }

        $opx = Get-ChildItem -LiteralPath $ext -Recurse -File -Filter 'opera.exe' -ErrorAction SilentlyContinue |
               Sort-Object { $_.FullName.Length } | Select-Object -First 1
        if (-not $opx) {
            Write-Log 'opera.exe NON trovato. Contenuto estratto:'
            Get-ChildItem -LiteralPath $ext -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 80 |
                ForEach-Object { Write-Log ('  ' + $_.FullName.Substring($ext.Length) + $(if ($_.PSIsContainer) { '\' } else { "  ($($_.Length))" })) }
            throw "opera.exe non trovato dopo l'estrazione: il layout dell'installer e' cambiato. Invia il log."
        }
        $base = $opx.DirectoryName
        $fv = [string]$opx.VersionInfo.FileVersion
        if ([string]::IsNullOrWhiteSpace($fv)) { $fv = $r.Version }
        $fv = $fv.Trim()
        Write-Log "opera.exe in '$base', FileVersion $fv"

        Set-Status $T.Install 100
        $upd = Join-Path $target 'updates'
        New-Item -ItemType Directory -Force -Path $upd | Out-Null

        $old = Read-VersionLog $target
        if ($old) {
            Remove-Item -LiteralPath (Join-Path $target 'Assets')     -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath (Join-Path $target $old.Version) -Recurse -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath (Join-Path $target $fv) -Recurse -Force -ErrorAction SilentlyContinue

        foreach ($f in 'opera.exe', 'opera.visualelementsmanifest.xml', 'Resources.pri') {
            $s = Join-Path $base $f
            if (Test-Path -LiteralPath $s) {
                Copy-Item -LiteralPath $s -Destination (Join-Path $target $f) -Force
                Remove-Item -LiteralPath $s -Force
            }
        }
        $assets = Join-Path $base 'Assets'
        if (Test-Path -LiteralPath $assets) {
            Remove-Item -LiteralPath (Join-Path $target 'Assets') -Recurse -Force -ErrorAction SilentlyContinue
            Move-Item -LiteralPath $assets -Destination (Join-Path $target 'Assets')
        }
        Move-Item -LiteralPath $base -Destination (Join-Path $target $fv)
        Set-Content -LiteralPath (Join-Path $upd 'Version.log') -Value ("$fv|$($d.Ring)|$($d.Arch)") -NoNewline -Encoding ASCII

        # Launcher e collegamento desktop
        $launcher = Join-Path $Root "$instName Launcher.exe"
        Update-Launcher $instName $target
        if ($script:Opt.Shortcut -and (Test-Path -LiteralPath $launcher)) {
            $lnk = Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) "$instName.lnk"
            if (-not (Test-Path -LiteralPath $lnk)) {
                $sh = New-Object -ComObject WScript.Shell
                $l = $sh.CreateShortcut($lnk)
                $l.IconLocation = "$target\opera.exe,0"; $l.WorkingDirectory = $Root; $l.TargetPath = $launcher
                $l.Save()
            }
        }
        Write-Log "Installato $instName $fv"
        Set-Status ($T.Done -f "$instName $fv") 0
        return 'installed'
    }
    finally {
        Remove-Item -LiteralPath $dl  -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $ext -Recurse -Force -ErrorAction SilentlyContinue
        if ((Test-Path -LiteralPath $WorkDir) -and -not (Get-ChildItem -LiteralPath $WorkDir -Force -ErrorAction SilentlyContinue)) {
            Remove-Item -LiteralPath $WorkDir -Force -ErrorAction SilentlyContinue
        }
    }
}

function Install-One([int]$i) {
    $loc = Get-LocalFor $i; $r = $script:Remote[$i]
    if ($loc -and $r -and $loc.Version -eq $r.Version -and -not $script:Opt.IgnoreVer) {
        if ($script:Console) { Write-Host $T.UpToDate } else { [void][System.Windows.Forms.MessageBox]::Show($T.UpToDate, $T.Title, 'OK', 'Information') }
        return
    }
    [void](Install-Ring $i $true)
}

# Equivalente di "Testing()" della versione C#: installa le varianti spuntate e aggiorna quelle installate
function Install-All {
    if ($script:Opt.Separate) {
        foreach ($arch in 'x86', 'x64') {
            $idx = 0..7 | Where-Object { $Rings[$_].Arch -eq $arch }
            $chk = if ($arch -eq 'x86') { $script:chk86 } else { $script:chk64 }
            $any = $idx | Where-Object { Test-Path -LiteralPath (Join-Path $Root "$($Rings[$_].Dir)\opera.exe") }
            if ($chk -and $chk.Checked -and -not $any) { foreach ($i in $idx) { if ($script:Remote[$i]) { [void](Install-Ring $i $false) } } }
        }
    }
    for ($i = 0; $i -lt 8; $i++) { if (Test-Outdated $i) { [void](Install-Ring $i $false) } }
}

# --- Launcher (compilato con csc.exe, come i vecchi "<cartella> Launcher.exe") ---------------------
function Update-Launcher([string]$instName, [string]$target) {
    $ErrorActionPreference = 'Continue'
    $out = Join-Path $Root "$instName Launcher.exe"
    $src = Join-Path $WorkDir 'Launcher.cs'; $tmpExe = Join-Path $WorkDir 'Launcher.exe'; $ico = Join-Path $WorkDir 'Launcher.ico'
    try {
        if ((Test-Path -LiteralPath $out) -and ((Get-Item -LiteralPath $out).VersionInfo.FileVersion -eq $LauncherVersion)) { return }
        $csc = @("$env:windir\Microsoft.NET\Framework64\v4.0.30319\csc.exe", "$env:windir\Microsoft.NET\Framework\v4.0.30319\csc.exe") |
               Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if (-not $csc) { throw 'csc.exe (.NET Framework 4) non trovato' }
        New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
        $code = $LauncherSource.Replace('__TITLE__', "$instName Launcher").Replace('__LVER__', $LauncherVersion).Replace('__INSTDIR__', $instName)
        [IO.File]::WriteAllText($src, $code, (New-Object Text.UTF8Encoding($true)))
        $cArgs = @('/nologo', '/target:winexe', '/optimize+', "/out:$tmpExe", '/reference:System.Windows.Forms.dll', '/reference:System.Drawing.dll')
        try {
            $ic = [System.Drawing.Icon]::ExtractAssociatedIcon((Join-Path $target 'opera.exe'))
            $fs = [IO.File]::Create($ico); try { $ic.Save($fs) } finally { $fs.Dispose() }
            $cArgs += "/win32icon:$ico"
        } catch { Write-Log "Icona launcher non estratta: $($_.Exception.Message)" }
        $cArgs += $src
        $o = & $csc @cArgs 2>&1
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $tmpExe)) { throw ('compilazione fallita: ' + (($o | Out-String).Trim())) }
        Move-Item -LiteralPath $tmpExe -Destination $out -Force
        Write-Log "Launcher creato: $out"
    }
    catch {
        Write-Log "Launcher non creato ($instName): $($_.Exception.Message)"
        $pre = Join-Path $Root "Bin\Launcher\$instName Launcher.exe"
        if (-not (Test-Path -LiteralPath $out) -and (Test-Path -LiteralPath $pre)) {
            Copy-Item -LiteralPath $pre -Destination $out; Write-Log 'Launcher precompilato copiato da Bin\Launcher'
        }
    }
    finally { Remove-Item -LiteralPath $src, $tmpExe, $ico -Force -ErrorAction SilentlyContinue }
}

# --- Autoaggiornamento da GitHub ---------------------------------------------------------------
# Opera-Updater.version = "<versione>|<sha256 di Opera-Updater.ps1>". Ritorna $true se ha aggiornato e rilanciato lo script.
function Invoke-SelfUpdate {
    if ($NoSelfUpdate -or [string]::IsNullOrWhiteSpace($SelfUpdateBase) -or $SelfUpdateBase -match 'YOUR_USER' -or -not $PSCommandPath) { return $false }
    $tmp = "$PSCommandPath.new"
    try {
        $base = $SelfUpdateBase.TrimEnd('/')
        $resp = Invoke-WebRequest -UseBasicParsing -Uri "$base/Opera-Updater.version" -TimeoutSec 10
        $txt  = if ($resp.Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($resp.Content) } else { [string]$resp.Content }
        $v = $txt.Trim([char]0xFEFF, ' ', "`r", "`n", "`t").Split('|')
        $newVer = $v[0].Trim(); $sha = if ($v.Count -gt 1) { $v[1].Trim() } else { '' }
        if ([version]$newVer -le [version]$ScriptVersion) { return $false }
        Write-Log "Autoaggiornamento: disponibile $newVer (attuale $ScriptVersion)"
        if (-not $script:Console) {
            $a = [System.Windows.Forms.MessageBox]::Show(($T.SelfUpd -f $newVer, $ScriptVersion), $T.Title, 'YesNo', 'Question')
            if ($a -ne 'Yes') { return $false }
        }
        Invoke-WebRequest -UseBasicParsing -Uri "$base/Opera-Updater.ps1" -OutFile $tmp -TimeoutSec 60
        if ($sha -and ((Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash -ne $sha)) { throw 'SHA256 non corrispondente' }
        $errs = $null; $tk = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($tmp, [ref]$tk, [ref]$errs)
        if ($errs -and $errs.Count) { throw 'il file scaricato non e'' uno script PowerShell valido' }
        Copy-Item -LiteralPath $PSCommandPath -Destination "$PSCommandPath.bak" -Force
        Move-Item -LiteralPath $tmp -Destination $PSCommandPath -Force
        Write-Log "Script aggiornato a $newVer (backup: $PSCommandPath.bak). Riavvio."
        $al = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath))
        if ($UpdateAll) { $al += '-UpdateAll' }
        Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList $al
        return $true
    }
    catch { Write-Log "Autoaggiornamento fallito: $($_.Exception.Message)"; return $false }
    finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
}

# --- Rilevamento impostazioni iniziali ---------------------------------------------------------
$sepFound = $Rings | Where-Object { Test-Path -LiteralPath (Join-Path $Root "$($_.Dir)\updates\Version.log") }
$script:Opt.Separate = [bool]$sepFound

# =================================================================================================
# Modalita' console (-UpdateAll)
# =================================================================================================
if ($script:Console) {
    Write-Log '--- avvio -UpdateAll'
    if (Invoke-SelfUpdate) { exit 0 }
    Refresh-Remote
    try { Install-All } catch { Show-Error $_.Exception.Message; exit 1 }
    Write-Host 'Fatto.'
    exit 0
}

# =================================================================================================
# GUI
# =================================================================================================
function Pt($x, $y) { New-Object System.Drawing.Point($x, $y) }
function Sz($w, $h) { New-Object System.Drawing.Size($w, $h) }
function New-Label([string]$text, $x, $y, $w = 0, $h = 0) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text; $l.Location = Pt $x $y
    if ($w) { $l.AutoSize = $false; $l.Size = Sz $w $h } else { $l.AutoSize = $true }
    $l
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "$($T.Title) $ScriptVersion"
$form.ClientSize = Sz 360 372
$form.FormBorderStyle = 'FixedSingle'; $form.MaximizeBox = $false; $form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
foreach ($ico in 'Opera Updater.ico', 'Opera Updater32.ico') {
    $p = Join-Path $Root $ico
    if (Test-Path -LiteralPath $p) { try { $form.Icon = New-Object System.Drawing.Icon($p); break } catch {} }
}
$tip = New-Object System.Windows.Forms.ToolTip

# Righe versioni
$grp1 = New-Object System.Windows.Forms.GroupBox
$grp1.Location = Pt 10 6; $grp1.Size = Sz 340 134
$script:Btn = New-Object object[] 8
$script:VerLbl = New-Object object[] 4
for ($k = 0; $k -lt 4; $k++) {
    $y = 18 + $k * 29
    $grp1.Controls.Add((New-Label $RowNames[$k] 10 ($y + 4)))
    $v = New-Label '...' 100 ($y + 4); $grp1.Controls.Add($v); $script:VerLbl[$k] = $v
    foreach ($a in 0, 1) {
        $i = $k + 4 * $a
        $b = New-Object System.Windows.Forms.Button
        $b.Text = $Rings[$i].Arch; $b.Tag = $i
        $b.Size = Sz 50 25; $b.Location = Pt (215 + 56 * $a) $y
        if ($a -eq 1 -and -not [Environment]::Is64BitOperatingSystem) { $b.Visible = $false }
        $b.Add_Click({ param($s, $e) Invoke-Op { param($idx) Install-One $idx } ([int]$s.Tag) })
        $grp1.Controls.Add($b); $script:Btn[$i] = $b
    }
}
$form.Controls.Add($grp1)

# Installa tutto
$grp2 = New-Object System.Windows.Forms.GroupBox
$grp2.Location = Pt 10 144; $grp2.Size = Sz 340 40
$grp2.Controls.Add((New-Label $T.LabelAll 10 15))
$script:chk86 = New-Object System.Windows.Forms.CheckBox; $script:chk86.Text = 'x86'; $script:chk86.AutoSize = $true; $script:chk86.Location = Pt 215 14
$script:chk64 = New-Object System.Windows.Forms.CheckBox; $script:chk64.Text = 'x64'; $script:chk64.AutoSize = $true; $script:chk64.Location = Pt 271 14
if (-not [Environment]::Is64BitOperatingSystem) { $script:chk64.Visible = $false }
$grp2.Controls.AddRange(@($script:chk86, $script:chk64))
$form.Controls.Add($grp2)
$script:grp2 = $grp2; $script:grp1 = $grp1

# Opzioni
$script:chkSep = New-Object System.Windows.Forms.CheckBox
$script:chkSep.Text = $T.Sep; $script:chkSep.AutoSize = $true; $script:chkSep.Location = Pt 16 196; $script:chkSep.Checked = $script:Opt.Separate
$script:chkIgn = New-Object System.Windows.Forms.CheckBox
$script:chkIgn.Text = $T.IgnoreVer; $script:chkIgn.AutoSize = $true; $script:chkIgn.Location = Pt 16 220
$script:chkLnk = New-Object System.Windows.Forms.CheckBox
$script:chkLnk.Text = $T.Shortcut; $script:chkLnk.AutoSize = $true; $script:chkLnk.Location = Pt 16 244
$form.Controls.AddRange(@($script:chkSep, $script:chkIgn, $script:chkLnk))

$script:btnAll = New-Object System.Windows.Forms.Button
$script:btnAll.Text = $T.InstallAll; $script:btnAll.Location = Pt 222 224; $script:btnAll.Size = Sz 128 28
$script:btnExit = New-Object System.Windows.Forms.Button
$script:btnExit.Text = $T.Exit; $script:btnExit.Location = Pt 275 258; $script:btnExit.Size = Sz 75 28
$form.Controls.AddRange(@($script:btnAll, $script:btnExit))

# Stato / progresso
$grp3 = New-Object System.Windows.Forms.GroupBox
$grp3.Location = Pt 10 292; $grp3.Size = Sz 340 72
$script:lblStatus = New-Label $T.Ready 8 16 220 20
$script:lblRight  = New-Label '' 200 16 132 20; $script:lblRight.TextAlign = 'TopRight'
$script:bar = New-Object System.Windows.Forms.ProgressBar
$script:bar.Location = Pt 8 42; $script:bar.Size = Sz 324 14
$grp3.Controls.AddRange(@($script:lblStatus, $script:lblRight, $script:bar))
$form.Controls.Add($grp3)

# --- Logica UI ---
function Refresh-UI {
    $green  = [System.Drawing.Color]::FromArgb(126, 205, 126)
    $red    = [System.Drawing.Color]::FromArgb(236, 112, 112)
    for ($i = 0; $i -lt 8; $i++) {
        $b = $script:Btn[$i]; $r = $script:Remote[$i]; $l = Get-LocalFor $i
        $b.UseVisualStyleBackColor = $true
        $b.Enabled = [bool]$r
        $tip.SetToolTip($b, '')
        if ($l) {
            $b.UseVisualStyleBackColor = $false
            $b.BackColor = if (Test-Outdated $i) { $red } else { $green }
            $tip.SetToolTip($b, $l.Version)
        }
    }
    for ($k = 0; $k -lt 4; $k++) {
        $r = $script:Remote[$k + 4]; if (-not $r) { $r = $script:Remote[$k] }
        $script:VerLbl[$k].Text = if ($r) { $r.Version } else { 'n/d' }
    }
    $sep = $script:Opt.Separate
    foreach ($pair in @(@($script:chk86, 0), @($script:chk64, 4))) {
        $any = 0..3 | Where-Object { Test-Path -LiteralPath (Join-Path $Root "$($Rings[$pair[1] + $_].Dir)\opera.exe") }
        $pair[0].Enabled = ($sep -and -not $any)
        if (-not $pair[0].Enabled) { $pair[0].Checked = $false }
    }
    $outdated = @(0..7 | Where-Object { Test-Outdated $_ })
    $script:btnAll.Text = if ($outdated.Count) { $T.UpdateAll } else { $T.InstallAll }
    $script:btnAll.Enabled = ($outdated.Count -gt 0) -or $script:chk86.Checked -or $script:chk64.Checked
}

function Invoke-Op([scriptblock]$Work, $Arg = $null) {
    if ($script:Busy) { return }
    $script:Busy = $true
    foreach ($c in $script:grp1, $script:grp2, $script:chkSep, $script:chkIgn, $script:chkLnk, $script:btnAll) { $c.Enabled = $false }
    try { & $Work $Arg }
    catch { if ($_.Exception.Message -ne $T.Aborted) { Show-Error $_.Exception.Message } else { Write-Log 'Annullato dall''utente' } }
    finally {
        $script:Busy = $false
        foreach ($c in $script:grp1, $script:grp2, $script:chkSep, $script:chkIgn, $script:chkLnk) { $c.Enabled = $true }
        Set-Status $T.Ready 0
        Refresh-UI
    }
}

$script:chkSep.Add_CheckedChanged({ $script:Opt.Separate = $script:chkSep.Checked; Refresh-UI })
$script:chkIgn.Add_CheckedChanged({ $script:Opt.IgnoreVer = $script:chkIgn.Checked })
$script:chkLnk.Add_CheckedChanged({ $script:Opt.Shortcut = $script:chkLnk.Checked })
$script:chk86.Add_CheckedChanged({ Refresh-UI })
$script:chk64.Add_CheckedChanged({ Refresh-UI })
$script:btnAll.Add_Click({ Invoke-Op { Install-All } })
$script:btnExit.Add_Click({ $form.Close() })
$form.Add_FormClosing({ $script:Abort = $true })
$form.Add_FormClosed({ Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue })

$form.Add_Shown({
    Write-Log '--- avvio GUI'
    Invoke-Op {
        if (Invoke-SelfUpdate) { $form.Close(); return }
        if (Get-Process -Name opera -ErrorAction SilentlyContinue) {
            [void][System.Windows.Forms.MessageBox]::Show($T.Running, $T.Title, 'OK', 'Exclamation')
        }
        Refresh-Remote
    }
})

Refresh-UI
[void]$form.ShowDialog()
