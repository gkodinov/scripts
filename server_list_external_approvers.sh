
#!/bin/sh
          REPO=MariaDB/server
          set -euo pipefail

          # List first 200 PRs lacking classification labels as JSON
          /opt/homebrew/bin/gh pr list \
            --repo "$REPO" \
            --search 'is:pr label:"External Contribution"  draft:false  created:>2025-11' \
            --limit 200 \
            -s all \
            --json number,reviews \
            --jq '[ map(select(.reviews[].state == "APPROVED"))  | .[] | .reviews[].author.login as $r | {"number":.number} + { review: $r }] | .[]' |
          while read -r pr; do
            pr_number=$(echo "$pr" | jq -r '.number')
            reviewer=$(echo "$pr" | jq -r '.review')

            # Check if reviewer is in the developers team
            if /opt/homebrew/bin/gh api \
              -H "Accept: application/vnd.github+json" \
              "/orgs/MariaDB/teams/developers/members/$reviewer" \
              >/dev/null 2>&1; then
              is_developer=1
            else
              is_developer=0
            fi
            # Check if reviewer is in the staff team
            if /opt/homebrew/bin/gh api \
              -H "Accept: application/vnd.github+json" \
              "/orgs/MariaDB/teams/staff/members/$reviewer" \
              >/dev/null 2>&1; then
              is_foundation=1
            else
              is_foundation=0
            fi

            if [[ "$is_foundation" -eq 0 ]]; then
              if [[ "$is_developer" -eq 0 ]]; then
                echo "PR#$pr_number has an external reviewer $reviewer"
              fi
            fi
          done
