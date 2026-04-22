{
  last_gen_comment_by_author:
      (
        ( . as $parent |
          .comments
            | map(select(.author.login == $parent.author.login))
            | max_by(.createdAt | fromdateiso8601)
            | .createdAt
        )
        | if ((. | length) > 0) then . | fromdateiso8601 else 0 end
      ),
  last_gen_comment_by_me:
      (
        (
          .comments
            | map(select(.author.login == "gkodinov"))
            | max_by(.createdAt | fromdateiso8601)
            | .createdAt
        )
        | if ((. | length) > 0) then . | fromdateiso8601 else 0 end
      )
}
