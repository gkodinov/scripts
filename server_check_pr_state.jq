{
  number: .number,
  mdev:
    (
      .title
        | if test("^MDEV-(?<a>[0-9]*).*")
          then capture("^MDEV-(?<a>[0-9]*).*").a
          else "" end
    ),
  req_count_me:
    (
      .reviewRequests
        | map(select(.login == "gkodinov"))             
        | length                                        
    ),                                                  
  req_count_others:                                     
    (                                                   
      .reviewRequests                                   
        | map(select(.login != "gkodinov"))             
        | length                                        
    ),                                                  
  reviewed_by_me:                                       
    (                                                   
      .reviews                                          
        | map(select(.author.login == "gkodinov"))      
        | length                                        
    ),                                                  
  approved_by_me:                                       
    (                                                   
      .reviews                                          
        | map(select(                                   
          .author.login == "gkodinov"                   
          and .state == "APPROVED"                      
        ))                                              
        | length                                        
    ),                                                  
  reviewed_by_others:                                   
    (                                                   
      .reviews                                          
        | map(select(                                   
          .author.login != "gkodinov"                   
           and .authorAssociation == "MEMBER"           
        ))                                              
        | length                                        
    ),                                                  
  approved_by_others:                                   
    (                                                   
      .reviews                                          
        | map(select(                                   
          .author.login != "gkodinov"                   
          and .authorAssociation == "MEMBER"            
          and .state == "APPROVED"))
        | length                                        
    ),                                                  
  days_since_last_update:                               
    (                                                   
      (                                                 
        (                                               
          now - (.updatedAt | fromdateiso8601)          
        )                                               
        / (24 * 3600)                                   
      )                                                 
      | round                                           
    ),
  last_comment_by_me:
      (
        (
          .reviews
            | map(select(.author.login == "gkodinov"))
            | max_by(.submittedAt | fromdateiso8601)
            | .submittedAt
        )
        | if ((. | length) > 0) then . | fromdateiso8601 else 0 end
      ),
  last_comment_by_author:
      (
        (
          .reviews
            | map(select(.authorAssociation == "CONTRIBUTOR"))
            | max_by(.submittedAt | fromdateiso8601)
            | .submittedAt
        )
        | if ((. | length) > 0) then . | fromdateiso8601 else 0 end
      ),
  last_changes_requested:
      (
        (
          .reviews
            | map(select(.authorAssociation == "MEMBER" and .state == "CHANGES_REQUESTED"))
            | max_by(.submittedAt | fromdateiso8601)
            | .submittedAt
        )
        | if ((. | length) > 0) then . | fromdateiso8601 else 0 end
      ),
  last_approval:
      (
        (
          .reviews
            | map(select(.authorAssociation == "MEMBER" and .state == "APPROVED"))
            | max_by(.submittedAt | fromdateiso8601)
            | .submittedAt
        )
        | if ((. | length) > 0) then . | fromdateiso8601 else 0 end
      )
}
