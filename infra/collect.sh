#!/usr/bin/env bash
# 두 서버의 ~/results 를 S3 를 거쳐 로컬로 받는다. destroy 전에 실행한다.
#
#   infra/collect.sh <받을 폴더>
set -euo pipefail
DEST=$(cd "$1" && pwd)
cd "$(dirname "$0")"

REGION=$(terraform output -raw region)
BUCKET=$(terraform output -raw results_bucket)

for role in app k6; do
	id=$(terraform output -raw "${role}_instance_id")
	params=$(python3 -c 'import json, sys; print(json.dumps({"commands": [sys.argv[1]]}))' \
		"sudo -u ubuntu -H bash -lc 'aws s3 cp ~/results s3://$BUCKET/$role/ --recursive --only-show-errors'")
	cid=$(aws ssm send-command --region "$REGION" --instance-ids "$id" \
		--document-name AWS-RunShellScript --parameters "$params" \
		--query Command.CommandId --output text)
	aws ssm wait command-executed --region "$REGION" --command-id "$cid" --instance-id "$id"
done

aws s3 sync "s3://$BUCKET" "$DEST" --region "$REGION" --only-show-errors
echo "▶ 받음: $DEST"
