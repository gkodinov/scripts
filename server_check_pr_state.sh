#!/bin/sh

topN=200
print_pr_url=0

helpFunction()
{
   echo ""
   echo "Usage: $0 -t topN -u"
   echo "\t-t Only output topN action items. 200 by default."
   echo "\t-u Print PR URLs instead of just number"
   echo "\t-? Help."
   exit 1 # Exit script after printing help
}

# Function to resolve the script path
get_script_dir() {
    local SOURCE=$0
    while [ -h "$SOURCE" ]; do # Resolve $SOURCE until the file is no longer a symlink
        DIR=$(cd -P "$(dirname "$SOURCE")" && pwd)
        SOURCE=$(readlink "$SOURCE")
        [[ $SOURCE != /* ]] && SOURCE=$DIR/$SOURCE # If $SOURCE was a relative symlink, resolve it relative to the symlink base directory
    done
    DIR=$(cd -P "$(dirname "$SOURCE")" && pwd)
    echo "$DIR"
}

while getopts "t:u?" opt
do
   case "$opt" in
      t ) topN="$OPTARG" ;;
      u ) print_pr_url=1 ;;
      ? ) helpFunction ;; # Print helpFunction in case parameter is non-existent
   esac
done


          script_dir=$(get_script_dir)
          set -euo pipefail
#          if [[ 1 -eq 0 ]]; then
          /opt/homebrew/bin/gh pr list \
            --repo "MariaDB/server" \
            --search 'is:open is:pr label:"External Contribution" draft:false' \
            --limit 200 \
            -s all \
            --json number,title,reviewRequests,reviews,updatedAt,author \
            --jq '.[]' \
             > raw.json
#          fi
          cat raw.json | jq -c -f $script_dir/server_check_pr_state.jq > prs.json
          n_prs=0
          n_failures=0
          n_processed=0
          n_actionables=0
          while read -r pr; do
            pr_number=$(echo "$pr" | jq -r '.number')
            mdev=$(echo "$pr" | jq -r '.mdev')
            request_count_me=$(echo "$pr" | jq -r '.req_count_me')
            request_count_others=$(echo "$pr" | jq -r '.req_count_others')
            reviewed_by_me=$(echo "$pr" | jq -r '.reviewed_by_me')
            approved_by_me=$(echo "$pr" | jq -r '.approved_by_me')
            reviewed_by_others=$(echo "$pr" | jq -r '.reviewed_by_others')
            approved_by_others=$(echo "$pr" | jq -r '.approved_by_others')
            days_since_last_update=$(echo "$pr" | jq -r '.days_since_last_update')
            last_comment_by_me=$(echo "$pr" | jq -r '.last_comment_by_me')
            last_comment_by_author=$(echo "$pr" | jq -r '.last_comment_by_author')
            failure=''
            action=''
            jira_status=''
            jira_assignee=''
            if [[ -z "$mdev" ]]; then
              failure="$failure ###no MDEV!###"
              action="Add the MDEV-NNNNN prefix"
            else
              # get the MDEV state

              curl -s --header @/Users/gkodinov/.jira.mariadb.org/curl_headers.txt https://jira.mariadb.org/rest/api/2/issue/MDEV-$mdev | jq '{ status: .fields.status.name, assignee: .fields.assignee.emailAddress}' > mdev.json
              jira_status=$(cat mdev.json | jq -r '.status')
              jira_assignee=$(cat mdev.json | jq -r '.assignee')
              if [[ -z "$jira_status" ]]; then
                failure="$failure ### No Jira status ###"
                action="fix the script"
              fi
            fi
#            echo "PR#$pr_number is:"
#            echo "  request_count_me: $request_count_me"
#            echo "  request_count_others: $request_count_others"
#            echo "  reviewed by me: $reviewed_by_me"
#            echo "  approved by me: $approved_by_me"
#            echo "  reviewed by others: $reviewed_by_others"
#            echo "  approved by others: $approved_by_others"
            request_count=$((request_count_me + request_count_others))
            reviewed=$((reviewed_by_me + reviewed_by_others))
            approved=$((approved_by_me + approved_by_others))

            state=''
            comment=''
            n_states=0

            # set the state

            if [[ $approved_by_me -gt 0 && $approved_by_others -gt 0 && $request_count -eq 0 ]]; then
              state="APPROVED"
              action="$action Push, Push, Push"
              n_states=$((n_states +1))
            fi
            if [[ $approved_by_me -gt 0 && $request_count_others -gt 0 ]]; then
              state="FINAL REVIEW"
              comment="waiting for the final reviewer"
              n_states=$((n_states +1))
              if [[ $days_since_last_update -ge 21 ]]; then
                action='Nag final reviewer'
              fi
            fi
            if [[ $approved_by_me -eq 0 && $request_count_others -gt 0 ]]; then
              state="FINAL REVIEW"
              comment="sans preliminary review, waiting for the final reviewer"
              n_states=$((n_states +1))
              if [[ $days_since_last_update -ge 21 ]]; then
                action='Nag final reviewer'
              fi
            fi
            if [[ $approved -eq 0 && $request_count -eq 0 && $reviewed -eq 0 ]]; then
              state="OPEN"
              comment="need preliminary review"
              action="$action Do preliminary review"
              n_states=$((n_states +1))
            fi
            if [[ $approved -eq 0 && $request_count -eq 0 && $reviewed_by_me -eq 0 && $reviewed_by_others -gt 0 ]]; then
              state="OPEN"
              comment="with comments, needs preliminary review"
              action="$action Do preliminary review"
              n_states=$((n_states +1))
            fi
            if [[ $approved -eq 0 && $request_count -eq 0 && $reviewed_by_me -gt 0 ]]; then
              state="PRELIMINARY REVIEW"
              if [[ $last_comment_by_me -gt $last_comment_by_author ]]; then
                comment="Waiting for the submitter to reply"
                if [[ $days_since_last_update -ge 21 ]]; then
                  action="$action Nag the submitter"
                fi
              else
                comment="Submitter replied"
                action="$action Reply to the submitter"
              fi
              n_states=$((n_states +1))
            fi
            if [[ $approved -eq 0 && $request_count_me -gt 0 && $request_count_others -eq 0 ]]; then
              state="PRELIMINARY REVIEW"
              comment="waiting for me"
	      action='Reply to preliminary review'
              n_states=$((n_states +1))
            fi
            if [[ $approved_by_me -eq 0 && $approved_by_others -gt 0 && $request_count -eq 0 ]]; then
              state="APPROVED"
              comment="sans preliminary review"
              action="$action Push, Push, Push"
              n_states=$((n_states +1))
            fi
            if [[ $approved_by_me -gt 0 && $approved_by_others -eq 0 && request_count -eq 0 ]]; then
              state="PRELIMINARY REVIEW DONE"
              comment="assign final reviewer"
              if [[ $days_since_last_update -ge 21 ]]; then
                action="$action, assign final reviewer"
              fi
              n_states=$((n_states +1))
            fi
            if [[ $approved_by_me -gt 0 && $approved_by_others -eq 0 && request_count_others -gt 0 ]]; then
              state="FINAL REVIEW"
              comment="wait for the final review"
              if [[ $days_since_last_update -ge 21 ]]; then
                action="$action, nag the final reviewer"
              fi
              n_states=$((n_states +1))
            fi

            if [[ -z "$state" ]]; then
              failure="$failure ###NO_STATE###"
              action="$action fix the state machine"
              n_states=$((n_states +1))
            fi
            if [[ $n_states -gt 1 ]]; then
              failure="$failure ###STATE_CONFLICT###"
              action="$action, fix the state machine"
              n_states=$((n_states +1))
            fi

            if [[ "$state" == "APPROVED" && "$jira_status" != "Approved" ]]; then
              failure="$failure Jira status $jira_status doesn't match PR state APPROVED"
              action="$action, update jira state to Approved"
            fi

            #print the outcome

            if [[ -n "$comment" ]]; then
              state="$state: $comment"
            fi
            if [[ ! ( -z "$failure" && -z $action ) ]]; then
              if [[ "$print_pr_url" -eq 0 ]]; then
                printf "PR#%d: " "$pr_number"
              else
                printf "https://github.com/MariaDB/server/pull/%d : " "$pr_number"
                open "https://github.com/MariaDB/server/pull/$pr_number"
                if [[ ! ( -z "$mdev" ) ]]; then
                  open "https://jira.mariadb.org/browse/MDEV-$mdev"
                fi
              fi
            fi

            if [[ -z "$failure" && -z $action ]]; then
              # echo "$state"
              n_processed=$((n_processed+1))
            elif [[ -z "$failure" ]]; then
              echo "ACTION: $action. State=$state"
              n_actionables=$((n_actionables+1))
            else
              echo "FAILURE=$failure, ACTION: $action. State=$state"
              n_failures=$((n_failures+1))
            fi
            n_prs=$((n_prs+1))
            n_actions=$((n_actionables + n_failures))
            if [[ $n_actions -ge $topN ]]; then
              break # Exit due to topN
            fi
          done < prs.json
          
          # final tally
          printf "%s visited, " "$n_prs"
          printf "%s failures, " "$n_failures"
          printf "%s actionables, " "$n_actionables"
          echo $n_processed OK
          rm prs.json
          rm raw.json
