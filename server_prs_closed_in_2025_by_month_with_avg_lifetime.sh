#!/bin/sh

set -euo pipefail

OWNER="MariaDB"
REPO="Server"
YEAR="2025"
MONTH="01"

echo '"Month","Count","Average_days"'
while [[ $MONTH -lt 13 ]] ; do
	START_DATE=$(printf '%04d-%02d-01T00:00:00Z' ${YEAR} ${MONTH})
	END_DATE="$(gdate -u -d "$START_DATE +1 month" +"%Y-%m-%dT%H:%M:%SZ")"

	total_seconds=0
	ctr=0
	pr_count=0

	pr_count=0
	gh pr list --state=all --limit=1000 --search "is:pr label:\"External Contribution\"  closed:${START_DATE}..${END_DATE}" --json createdAt,closedAt | jq -r '.[] | [.createdAt, .closedAt] | @tsv' > prs.tsv
	while IFS=$'\t' read -r CREATED CLOSED; do
	    pr_count=$((pr_count + 1))
	    CREATED_EPOCH=$(gdate -u -d "$CREATED" +%s)
	    CLOSED_EPOCH=$(gdate -u -d "$CLOSED" +%s)
	    DURATION=$((CLOSED_EPOCH - CREATED_EPOCH))

	    total_seconds=$((total_seconds + DURATION))
	    ctr=$((ctr + 1))
	done < prs.tsv

        closed=$ctr
	if [[ "$ctr" -eq 0 ]]; then
          avg_days=0
        else
	  AVG_SECONDS=$((total_seconds / ctr))
	  AVG_HOURS=$(awk "BEGIN { printf \"%.2f\", $AVG_SECONDS / 3600 }")
	  AVG_DAYS=$(awk "BEGIN { printf \"%.2f\", $AVG_SECONDS / 86400 }")
          avg_days=$AVG_DAYS
	fi
        printf '"%d", "%d", "%f"\n' ${MONTH} $ctr $avg_days
        MONTH=$((MONTH + 1))
done
