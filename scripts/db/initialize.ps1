$ErrorActionPreference = 'Stop'

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectDirectory = Split-Path -Parent (Split-Path -Parent $scriptDirectory)
$localConfigPath = Join-Path $projectDirectory 'src\main\resources\application-local.properties'

if (-not (Test-Path $localConfigPath)) {
	throw 'src/main/resources/application-local.properties 파일이 없습니다. application-local.example.properties를 복사해 값을 설정하세요.'
}

function Get-LocalProperty([string]$key) {
	$escapedKey = [regex]::Escape($key)
	$line = Get-Content $localConfigPath | Where-Object { $_ -match "^\s*$escapedKey\s*=" } | Select-Object -First 1
	if ($null -eq $line) {
		throw "$key 값을 src/main/resources/application-local.properties에 설정하세요."
	}
	return ($line -split '=', 2)[1].Trim()
}

$dbHost = Get-LocalProperty 'db.host'
$dbPort = Get-LocalProperty 'db.port'
$dbName = Get-LocalProperty 'db.name'
$dbUsername = Get-LocalProperty 'db.username'
$dbPassword = Get-LocalProperty 'db.password'
$mysqlArguments = @("--host=$dbHost", "--port=$dbPort", "--user=$dbUsername")

if (-not [string]::IsNullOrEmpty($dbPassword)) {
	$mysqlArguments += "--password=$dbPassword"
}

$schemaPath = (Join-Path $scriptDirectory 'schema.sql').Replace('\', '/')
$dataPath = (Join-Path $scriptDirectory 'data.sql').Replace('\', '/')

& mysql @mysqlArguments '--default-character-set=utf8mb4' $dbName --execute "source $schemaPath"
& mysql @mysqlArguments '--default-character-set=utf8mb4' $dbName --execute "source $dataPath"

Write-Host "MySQL 초기화가 완료되었습니다: $dbName"
