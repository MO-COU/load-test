#!/usr/bin/env bash
# 측정 1회를 SSM 으로 돌린다. CONTRIBUTING 의 측정 절차를 순서대로 부른다.
#
#   infra/run.sh <이름> <브랜치> [커넥션 풀] [redis]
#   infra/run.sh pess-1 exp/pessimistic-lock
#   infra/run.sh lua-1 exp/redis-lua 16 redis
#
# terraform apply 뒤 두 서버에 /var/lib/load-test-ready 가 생기고 나서 실행한다.
set -euo pipefail
cd "$(dirname "$0")"

NAME=$1
BRANCH=$2
POOL=${3:-16}
REDIS=${4:-}

REGION=$(terraform output -raw region)
APP=$(terraform output -raw app_instance_id)
K6=$(terraform output -raw k6_instance_id)

# SSM 은 root 로 돈다. 세팅 스크립트는 ubuntu 홈을 전제로 하므로 ubuntu 로 바꿔 실행한다.
remote() {
	local id=$1 cmd=$2 params cid status
	params=$(python3 -c 'import json, sys; print(json.dumps({"commands": [sys.argv[1]], "executionTimeout": ["900"]}))' \
		"sudo -u ubuntu -H bash -lc 'set -o pipefail; $cmd'")
	cid=$(aws ssm send-command --region "$REGION" --instance-ids "$id" \
		--document-name AWS-RunShellScript --parameters "$params" \
		--query Command.CommandId --output text)
	while true; do
		sleep 3
		status=$(aws ssm get-command-invocation --region "$REGION" --command-id "$cid" --instance-id "$id" \
			--query Status --output text 2>/dev/null || echo Pending)
		case $status in
			Pending | InProgress | Delayed) ;;
			*) break ;;
		esac
	done
	aws ssm get-command-invocation --region "$REGION" --command-id "$cid" --instance-id "$id" \
		--query StandardOutputContent --output text
	if [ "$status" != Success ]; then
		aws ssm get-command-invocation --region "$REGION" --command-id "$cid" --instance-id "$id" \
			--query StandardErrorContent --output text >&2
		echo "▶ 실패: $cmd ($status)" >&2
		exit 1
	fi
}

echo "▶ $NAME · $BRANCH · 커넥션 풀 $POOL"
remote "$APP" "mkdir -p ~/results && ~/app.sh $BRANCH $POOL 2>&1 | tee ~/results/app-$NAME.txt"
remote "$APP" "~/before.sh $NAME $REDIS"
remote "$K6" "~/k6.sh $NAME | tail -45"
remote "$APP" "~/drain.sh | tee ~/results/drain-$NAME.txt"
remote "$APP" "~/after.sh $NAME"
