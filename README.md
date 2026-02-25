This is a set of scripts against github and jira public APIs to automate various tasks of my daily job.
Tested to work on a MacOSX.

Some useful bash aliases to have:

```
alias pr_action='sh $HOME/dev/gkodinov/scripts/server_check_pr_state.sh -t1 -u'
alias pr_action_fetch='sh $HOME/dev/gkodinov/scripts/server_check_pr_state.sh -t1 -f'
alias pr_action_local='sh $HOME/dev/gkodinov/scripts/server_check_pr_state.sh -t1 -n -f'
alias pr_action_local_debug='sh -x $HOME/dev/gkodinov/scripts/server_check_pr_state.sh -t1 -n -f'
alias pr_labels='sh $HOME/dev/gkodinov/scripts/server_assign_gh_pr_labels.sh'
```
