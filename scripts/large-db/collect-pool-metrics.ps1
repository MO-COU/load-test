# 커넥션 풀(HikariCP) - Tomcat 워커 스레드 - InnoDB 버퍼 풀 사용량을
# 1초 간격으로 기록한다. k6 부하를 돌리기 직전에 별도 PowerShell 창에서
# 실행하고, 부하가 끝나면 Ctrl+C로 멈춘다.
#
#   .\scripts\large-db\collect-pool-metrics.ps1 -Name insert-only-stage0
#
# 결과: docs\benchmark-results\sync-vs-async\raw\<Name>.tsv
#
# 사전 확인(최초 1회): 실제 지표 이름이 스크립트가 찾는 이름과 같은지 확인한다.
#   curl -s localhost:8080/actuator/prometheus | Select-String -Pattern 'hikaricp_connections|tomcat_threads'

param(
    [Parameter(Mandatory = $true)]
    [string]$Name,
    [string]$BaseUrl = "http://localhost:8080",
    [int]$IntervalSeconds = 1,
    [string]$ComposeFile = "docker-compose.large-db.yml",
    [string]$DbContainer = "mysql-large",
    [string]$DbUser = "coupon_large",
    [string]$DbPassword = "coupon-large-1234",
    [string]$DbName = "coupon_large"
)

$ErrorActionPreference = "Continue"

$OutDir = "docs/benchmark-results/sync-vs-async/raw"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutFile = Join-Path $OutDir "$Name.tsv"

$header = "timestamp`thikari_active`thikari_pending`ttomcat_busy`ttomcat_max`tinnodb_buf_reads`tinnodb_buf_read_requests`tinnodb_buf_pages_free`tinnodb_buf_pages_total`tinnodb_os_log_fsyncs`tinnodb_row_lock_waits"
Set-Content -Path $OutFile -Value $header -Encoding utf8

Write-Host "기록 시작 -> $OutFile (Ctrl+C로 종료, ${IntervalSeconds}초 간격)"

$innodbSql = "SHOW GLOBAL STATUS WHERE Variable_name IN ('Innodb_buffer_pool_reads','Innodb_buffer_pool_read_requests','Innodb_buffer_pool_pages_free','Innodb_buffer_pool_pages_total','Innodb_os_log_fsyncs','Innodb_row_lock_waits');"

function Get-MetricValue {
    param([string]$Text, [string]$Prefix)
    if ([string]::IsNullOrEmpty($Text)) { return "NA" }
    $line = ($Text -split "`n") | Where-Object { $_.StartsWith($Prefix) } | Select-Object -First 1
    if ($null -eq $line) { return "NA" }
    $parts = $line -split '\s+'
    return $parts[$parts.Length - 1]
}

function Get-InnodbValue {
    param([hashtable]$Map, [string]$Key)
    if ($Map.ContainsKey($Key)) { return $Map[$Key] }
    return "NA"
}

while ($true) {
    try {
        $metrics = (Invoke-WebRequest -Uri "$BaseUrl/actuator/prometheus" -UseBasicParsing -ErrorAction Stop).Content
    } catch {
        $metrics = ""
    }

    $hikariActive = Get-MetricValue -Text $metrics -Prefix "hikaricp_connections_active"
    $hikariPending = Get-MetricValue -Text $metrics -Prefix "hikaricp_connections_pending"
    $tomcatBusy = Get-MetricValue -Text $metrics -Prefix "tomcat_threads_busy"
    $tomcatMax = Get-MetricValue -Text $metrics -Prefix "tomcat_threads_config_max"

    $innodb = @{}
    try {
        $innodbRaw = docker compose -f $ComposeFile exec -T $DbContainer mysql "-u$DbUser" "-p$DbPassword" -N -e $innodbSql $DbName 2>$null
        if ($innodbRaw) {
            foreach ($line in $innodbRaw) {
                $cols = $line -split '\s+'
                if ($cols.Length -ge 2) { $innodb[$cols[0]] = $cols[1] }
            }
        }
    } catch { }

    $bufReads = Get-InnodbValue $innodb "Innodb_buffer_pool_reads"
    $bufReadRequests = Get-InnodbValue $innodb "Innodb_buffer_pool_read_requests"
    $bufPagesFree = Get-InnodbValue $innodb "Innodb_buffer_pool_pages_free"
    $bufPagesTotal = Get-InnodbValue $innodb "Innodb_buffer_pool_pages_total"
    $osLogFsyncs = Get-InnodbValue $innodb "Innodb_os_log_fsyncs"
    $rowLockWaits = Get-InnodbValue $innodb "Innodb_row_lock_waits"

    $timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $row = "$timestamp`t$hikariActive`t$hikariPending`t$tomcatBusy`t$tomcatMax`t$bufReads`t$bufReadRequests`t$bufPagesFree`t$bufPagesTotal`t$osLogFsyncs`t$rowLockWaits"

    Write-Host $row
    Add-Content -Path $OutFile -Value $row

    Start-Sleep -Seconds $IntervalSeconds
}
