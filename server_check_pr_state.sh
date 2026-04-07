#!/bin/sh

topN=200
print_pr_url=0
fetch_pr_list=1
delete_cache_files=1
skip_prs=""
do_pr=""

helpFunction()
{
   echo ""
   echo "Usage: $0 -t topN -u"
   echo "\t-t Only output topN action items. 200 by default."
   echo "\t-u Print PR URLs instead of just number"
   echo "\t-n do not fetch PR list. rely on local files"
   echo "\t-f do not delete local cache files"
   echo "\t-s Skip the PRs mentioned in this list. Takes an argument a list of PR numbers"
   echo "\t-i Filter only this PR. Takes the ID as an argument"
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

CheckPRGenComments() {
  if [[ $fetch_pr_list -gt 0 ]]; then
    /opt/homebrew/bin/gh pr list \
      --repo "MariaDB/server" \
      --search "id == $pr_number" \
      --limit 1 \
      -s all \
      --json number,author,comments \
      --jq '.[]' \
       > raw_comments.json
  fi
  cat raw_comments.json | jq -c -f $script_dir/server_check_pr_state_comments.jq > pr_comments.json
  local pr=''
  read -r pr < pr_comments.json
  if [[ $delete_cache_files -gt 0 ]]; then
    rm pr_comments.json
    rm raw_comments.json
  fi
  local last_gen_comment_by_me=$(echo "$pr" | jq -r '.last_gen_comment_by_me')
  local last_gen_comment_by_author=$(echo "$pr" | jq -r '.last_gen_comment_by_author')
  local last_by_me=$last_comment_by_me
  if [[ $last_gen_comment_by_me -gt $last_comment_by_me ]]; then
    local last_by_me=$last_gen_comment_by_me
  fi
  last_by_author=$last_comment_by_author
  if [[ $last_gen_comment_by_author -gt $last_comment_by_author ]]; then
    local last_by_author=$last_gen_comment_by_author
  fi

  if [[ $last_by_me -gt $last_by_author ]]; then
    echo 1
  else
    echo 0
  fi
}

CountBBPending() {
  if [[ $fetch_pr_list -gt 0 ]]; then
    /opt/homebrew/bin/gh pr list \
      --repo "MariaDB/server" \
      --search "id == $pr_number" \
      --limit 1 \
      -s all \
      --json statusCheckRollup \
      --jq '.[] | .statusCheckRollup | map(select(.state == "PENDING")) | length' \
       > pr_pending.json
  fi
  local pending=''
  read -r pending < pr_pending.json
  if [[ $delete_cache_files -gt 0 ]]; then
    rm pr_pending.json
  fi
  echo $pending
}

while getopts "t:u?fns:i:" opt
do
   case "$opt" in
      t ) topN="$OPTARG" ;;
      u ) print_pr_url=1 ;;
      n ) fetch_pr_list=0 ;;
      f ) delete_cache_files=0 ;;
      s ) skip_prs="$OPTARG" ;;
      i ) do_pr="$OPTARG" ;;
      ? ) helpFunction ;; # Print helpFunction in case parameter is non-existent
   esac
done


          script_dir=$(get_script_dir)
          set -euo pipefail
          filter='is:open is:pr label:"External Contribution" draft:false'
          if [[ $do_pr -gt 0 ]]; then
            filter+=" id == $do_pr"
          fi
          if [[ $fetch_pr_list -gt 0 ]]; then
            /opt/homebrew/bin/gh pr list \
              --repo "MariaDB/server" \
              --search "$filter" \
              --limit 200 \
              -s all \
              --json number,title,reviewRequests,reviews,updatedAt,author,labels \
              --jq '.[]' \
               > raw.json
          fi
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
            last_changes_requested=$(echo "$pr" | jq -r '.last_changes_requested')
            last_approval=$(echo "$pr" | jq -r '.last_approval')
            is_in_rework=$(echo "$pr" | jq -r '.is_in_rework')
            state=''
            comment=''
            failure=''
            action=''
            jira_status=''
            jira_assignee_name=''
            jira_assignee_email=''

            request_count=$((request_count_me + request_count_others))
            reviewed=$((reviewed_by_me + reviewed_by_others))
            approved=$((approved_by_me + approved_by_others))
            n_states=0

            if [[ $skip_prs == *$pr_number* ]]; then
               state="SKIPPED"
               comment="Skipped from the command line"
              continue
            fi

            if [[ $is_in_rework -gt 0 ]]; then
               state="IN REWORK"
               comment="In internal rework. Skipping"
               continue
            fi

            if [[ -z "$mdev" ]]; then
              state="NO MDEV"
              comment="Add the MDEV-NNNNN prefix"
              if [[ $reviewed_by_me -eq 0 && $approved_by_me -eq 0 ]]; then
                action="Add MDEV"
              fi
              n_states=$((n_states +1))
            else
              # set the state

              if [[ $approved_by_me -gt 0 && $approved_by_others -gt 0 && $request_count -eq 0 && $last_approval > $last_changes_requested ]]; then
                state="APPROVED"
                pending=$(CountBBPending)
                if [[ pending -eq 0 ]]; then
                  action="$action Push, Push, Push"
                fi
                hrs_since_last_approval=$(((now_date_secs - $last_approval) / 60 / 60))
                if [[ $hrs_since_last_approval -gt 48 ]]; then
                  action="$action Check the Buildbot hosts"
                fi
                n_states=$((n_states +1))
              fi
              if [[ $approved_by_me -gt 0 && $approved_by_others -gt 0 && $request_count -eq 0 && $last_approval < $last_changes_requested ]]; then
                state="FINAL REVIEW"
                comment="waiting for subsequent reviews"
                n_states=$((n_states +1))
              fi
              if [[ $approved -eq 0 && $request_count_others -gt 0 ]]; then
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
                pr_comment_result=$(CheckPRGenComments)
                if [[ $pr_comment_result -gt 0 ]]; then
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
              if [[ $request_count_me -gt 0 && $request_count_others -eq 0 ]]; then
                state="PRELIMINARY REVIEW"
                comment="waiting for me"
                action='Reply to the preliminary review request'
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
                  action="$action, nag the final reviewer"
                fi
                n_states=$((n_states +1))
              fi
              if [[ $approved_by_me -gt 0 && $request_count_me -eq 0 && $request_count_others -gt 0 && $approved_by_others -eq 0 ]]; then
                state="FINAL REVIEW"
                comment="wait for the final review"
                if [[ $days_since_last_update -ge 21 ]]; then
                  action="$action, nag the final reviewer"
                fi
                n_states=$((n_states +1))
              fi
              if [[ $request_count_me -gt 0 && $approved_by_me -gt 0 ]]; then
                state="PRELIMINARY REVIEW RE-REQUESTED"
                comment="re-do the preliminary review as requested"
                action="$action re-do the preliminary review"
                n_states=$((n_states +1))
              fi
              if [[ $request_count_others -gt 0 && $approved_by_others -gt 0 ]]; then
                state="FINAL REVIEW RE-REQUESTED"
                comment="ask the reviewer to re-do the final review as requested"
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

              if [[ -z "$failure" && \
                   ( \
                     "$state" == "APPROVED" || \
                     "$state" == "FINAL REVIEW" || \
                     "$state" == "FINAL REVIEW RE-REQUESTED" \
                   ) \
                 ]]; then
                # get the MDEV state and check it

                curl -s --header \
                    @/Users/gkodinov/.jira.mariadb.org/curl_headers.txt \
                    https://jira.mariadb.org/rest/api/2/issue/MDEV-$mdev \
                  | jq '{ status: .fields.status.name,
                          assignee: .fields.assignee,
                          days_since_update:
                            ((
                                (now -
                                 ( .fields.updated | .[:19] | strptime("%Y-%m-%dT%T") | mktime)
                                ) /
                                (24 *3600)
                             ) | round) }' > mdev.json
                jira_status=$(cat mdev.json | jq -r '.status')
                jira_assignee_email=$(cat mdev.json | jq -r '.assignee.emailAddress')
                jira_assignee_name=$(cat mdev.json | jq -r '.assignee.name')
                jira_days_since_update=$(cat mdev.json | jq -r '.days_since_update')
                now_date_secs=`gdate +%s`
                if [[ $delete_cache_files -gt 0 ]]; then
                  rm mdev.json
                fi
                if [[ -z "$jira_status" ]]; then
                  failure="$failure ### No Jira status ###"
                  action="fix the script"
                fi

                if [[ "$jira_assignee_name" != "gkodinov" && \
                      "$jira_status" != "In Review" && "$jira_status" != "In Testing" && \
                      ( \
                        "$state" == "FINAL REVIEW" || \
                        "$state" == "FINAL REVIEW RE-REQUESTED" \
                      ) \
                   ]]; then
                  action="$action, update Jira state to 'In Testing' or 'In Review'"
                  failure="$failure Jira status $jira_status assignee $jira_assignee_name doesn't match PR state $state"
                  comment=""
                fi
                if [[ "$jira_assignee_name" == "gkodinov" && \
                      "$jira_status" != "Stalled" && \
                      ( \
                        "$state" == "FINAL REVIEW" || \
                        "$state" == "FINAL REVIEW RE-REQUESTED" \
                      ) \
                   ]]; then
                  action="$action, update Jira state to 'In Testing' or 'In Review'"
                  failure="$failure Jira status $jira_status assignee $jira_assignee_name doesn't match PR state $state"
                  comment=""
                fi
                if [[ "$jira_status" == "In Testing" && \
                      ( \
                        "$state" == "APPROVED" || \
                        "$state" == "FINAL REVIEW RE-REQUESTED" \
                      ) \
                   ]]; then
                  action=""
                  comment="Wait for testing to complete"
                  state="IN_TESTING"
                  if [[ $days_since_last_update -ge 21 && $jira_days_since_update -ge 21 ]]; then
                    action="Nag the tester"
                  fi
                fi

                if [[ "$state" == "APPROVED" && "$jira_status" != "Approved" ]]; then
                  failure="$failure Jira status $jira_status doesn't match PR state APPROVED"
                  action="$action, update jira state to Approved"
                fi
              fi
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
                if [[ ! ( -z "$mdev" ) ]]; then
                  open "https://jira.mariadb.org/browse/MDEV-$mdev"
                fi
                open "https://github.com/MariaDB/server/pull/$pr_number"
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
          if [[ $delete_cache_files -gt 0 ]]; then
            rm prs.json
            rm raw.json
          fi
