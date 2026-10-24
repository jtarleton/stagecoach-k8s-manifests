#!/bin/sh
# Checks the public endpoints, then pings healthchecks.io: the check URL on
# success, /fail with the failures as the body otherwise.
set -u
failed=""

# check NAME METHOD URL EXPECTED_STATUS [BODY_MUST_CONTAIN]
check() {
  code=$(curl -s -o /tmp/body -w '%{http_code}' -m 20 -X "$2" -A 'stagecoach-uptime' "$3") || code=000
  if [ "$code" != "$4" ]; then
    failed="$failed$1: HTTP $code (want $4)\n"
  elif [ -n "${5:-}" ] && ! grep -q "$5" /tmp/body; then
    failed="$failed$1: body lacks '$5'\n"
  fi
}

check front GET https://stagecoach.sh/ 200 'stagecoach'
check signup GET https://stagecoach.sh/signup 200 '<altcha-widget'
check altcha GET https://stagecoach.sh/altcha/v1/challenge 200 '"signature"'
check charts GET https://charts.stagecoach.sh/index.yaml 200 'stagecoach-agent'
# Unauthenticated agent call: 401 proves edge -> stage-coach (Go) is up.
check agent-api POST https://api.stagecoach.sh/v1/agent/clusters 401

if [ -z "$failed" ]; then
  echo "all checks passed"
  curl -fsS -m 10 --retry 3 -o /dev/null "$HC_PING_URL"
else
  printf "%b" "$failed"
  printf "%b" "$failed" | curl -fsS -m 10 --retry 3 -o /dev/null --data-binary @- "$HC_PING_URL/fail"
  exit 1
fi
