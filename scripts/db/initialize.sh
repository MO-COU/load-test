#!/usr/bin/env bash
set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_directory="$(cd "${script_directory}/../.." && pwd)"
local_config_path="${project_directory}/src/main/resources/application-local.properties"

if [[ ! -f "${local_config_path}" ]]; then
	echo 'src/main/resources/application-local.properties 파일이 없습니다. application-local.example.properties를 복사해 값을 설정하세요.' >&2
	exit 1
fi

read_property() {
	local key="$1"
	local value
	value="$(sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*//p" "${local_config_path}" | head -n 1)"
	if [[ -z "${value}" && "${key}" != "db.password" ]]; then
		echo "${key} 값을 src/main/resources/application-local.properties에 설정하세요." >&2
		exit 1
	fi
	echo "${value}"
}

db_host="$(read_property 'db.host')"
db_port="$(read_property 'db.port')"
db_name="$(read_property 'db.name')"
db_username="$(read_property 'db.username')"
db_password="$(read_property 'db.password')"
mysql_arguments=("--host=${db_host}" "--port=${db_port}" "--user=${db_username}")

if [[ -n "${db_password}" ]]; then
	mysql_arguments+=("--password=${db_password}")
fi

mysql "${mysql_arguments[@]}" --default-character-set=utf8mb4 "${db_name}" < "${script_directory}/schema.sql"
mysql "${mysql_arguments[@]}" --default-character-set=utf8mb4 "${db_name}" < "${script_directory}/data.sql"

echo "MySQL 초기화가 완료되었습니다: ${db_name}"
