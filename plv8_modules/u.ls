## BEG PURE FUNCTIONS ##

# will not mutate operand (similar to hashish.merge)
export merge = merge = (...args) ->
  r = (rval, hval) -> rval <<< hval
  args.reduce r, {}

# turn a title into a unique uri
export title2slug = (title, id) ->
  title = title.to-lower-case!
  title = title.replace new RegExp('[^a-z0-9 ]', 'g'), ''
  title = title.replace new RegExp(' +', 'g'), '-'
  title = title.slice 0, 30
  if id
    title = title.concat "-#{id}"
  title

## END PURE FUNCTIONS ##

top-forums-recent = (limit, fields='*') ->
  sql = """
  SELECT #{fields} FROM forums
  WHERE parent_id IS NULL AND site_id=$1
  ORDER BY created DESC, id ASC
  LIMIT $2
  """
  (...args) -> plv8.execute sql, args.concat([limit])

top-forums-active = (limit) ->
  sql = '''
  SELECT
    f.*,
    (SELECT AVG(EXTRACT(EPOCH FROM created)) FROM posts WHERE forum_id=f.id AND archived='f') sort
  FROM forums f
  WHERE parent_id IS NULL AND site_id=$1
  ORDER BY sort
  LIMIT $2
  '''
  (...args) -> plv8.execute sql, args.concat([limit])

sub-forums = ->
  sql = '''
  SELECT *
  FROM forums
  WHERE parent_id=$1
  ORDER BY created DESC, id DESC
  '''
  plv8.execute sql, arguments

export top-posts-recent = top-posts-recent = (limit, fields='p.*') ->
  sql = """
  SELECT
    #{fields},
    MIN(a.name) user_name,
    COUNT(p2.id) post_count
  FROM aliases a,
       posts p LEFT JOIN posts p2 ON p2.parent_id = p.id
  WHERE a.user_id=p.user_id
    AND a.site_id=1
    AND p.parent_id IS NULL
    AND p.forum_id=$1
    AND p.archived='f'
  GROUP BY p.id
  ORDER BY p.created DESC, id ASC
  LIMIT $2
  """
  (...args) -> plv8.execute sql, args.concat([limit])

top-posts-active = (limit, fields='p.*') ->
  sql = """
  SELECT
    #{fields},
    MIN(a.name) user_name,
    COUNT(p2.id) post_count,
    (SELECT AVG(EXTRACT(EPOCH FROM created)) FROM posts WHERE forum_id=$1 AND archived='f') sort
  FROM aliases a,
       posts p LEFT JOIN posts p2 ON p2.parent_id = p.id
  WHERE a.user_id=p.user_id
    AND a.site_id=1
    AND p.parent_id IS NULL
    AND p.forum_id=$1
    AND p.archived='f'
  GROUP BY p.id
  ORDER BY sort
  LIMIT $2
  """
  (...args) -> plv8.execute sql, args.concat([limit])

sub-posts = ->
  sql = '''
  SELECT p.*, a.name user_name
  FROM posts p, aliases a
  WHERE a.user_id=p.user_id
    AND a.site_id=1
    AND p.parent_id=$1
    AND p.archived='f'
  ORDER BY created DESC, id ASC
  '''
  plv8.execute sql, arguments

# recurses to build entire comment tree
export sub-posts-tree = sub-posts-tree = (parent-id, depth=3) ->
  sp = sub-posts(parent-id)
  if depth <= 0
    # more-posts flag will be used to put 'load more' links,
    # vs not showing the 'load more' links when there are no children yet
    # we only show 'load more' links when we hit an empty child list
    # and if and only if more-posts flag is true
    [merge(p, {posts: [], more-posts: !!sub-posts(p.id).length}) for p in sp]
  else
    [merge(p, {posts: sub-posts-tree(p.id, depth - 1)}) for p in sp]

# gets entire list of top posts and inlines all sub-posts to them
posts-tree = (forum-id, top-posts) ->
  [merge(p, {posts: sub-posts-tree(p.id)}) for p in top-posts]

decorate-forum = (f, top-posts-fun) ->
  merge f, {posts: posts-tree(f.id, top-posts-fun(f.id)), forums: [decorate-forum(sf, top-posts-fun) for sf in sub-forums(f.id)]}

export doc = ->
  if res = plv8.execute('SELECT json FROM docs WHERE site_id=$1 AND type=$2 AND key=$3', arguments)[0]
    JSON.parse(res.json)
  else
    null

export put-doc = (...args) ->
  insert-sql =
    'INSERT INTO docs (site_id, type, key, json) VALUES ($1, $2, $3, $4)'
  update-sql =
    'UPDATE docs SET json=$4 WHERE site_id=$1::bigint AND type=$2::varchar(64) AND key=$3::varchar(64)'

  args[3] = JSON.stringify args[3] if args[3]

  try
    plv8.subtransaction ->
      plv8.execute insert-sql, args
  catch
    plv8.execute update-sql, args

  true # rval

# single forum
forum-tree = (forum-id, top-posts-fun) ->
  sql = 'SELECT id,parent_id,title,slug,description,media_url,classes FROM forums WHERE id=$1 LIMIT 1'
  if f = plv8.execute(sql, [forum-id])[0]
    decorate-forum(f, top-posts-fun)

# all forums for site
forums-tree = (site-id, top-posts-fun, top-forums-fun) ->
  [decorate-forum(f, top-posts-fun) for f in top-forums-fun(site-id)]

export uri-for-forum = (forum-id) ->
  sql = 'SELECT parent_id, slug FROM forums WHERE id=$1'
  [{parent_id, slug}] = plv8.execute sql, [forum-id]
  if parent_id
    @uri-for-forum(parent_id) + '/' + slug
  else
    '/' + slug

export uri-for-post = (post-id, first-slug = null) ->
  sql = 'SELECT forum_id, parent_id, slug FROM posts WHERE id=$1'
  [{forum_id, parent_id, slug}] = plv8.execute sql, [post-id]
  if parent_id
    if first-slug
      @uri-for-post(parent_id, first-slug) # carry first slug thru
    else
      @uri-for-post(parent_id, slug) # set slug once, and only once at the beginning
  else
    if first-slug
      @uri-for-forum(forum_id) + '/t/' + slug + '/' + first-slug
    else
      @uri-for-forum(forum_id) + '/t/' + slug

export menu = (site-id) ->
  forums-tree(site-id,
    top-posts-recent(null, 'p.created,p.title,p.slug,p.id'),
    top-forums-recent(null, 'id,title,slug,classes'))

export build-forum-docs = (site-id, forum-id) ->
  menu = @menu(site-id)

  build-forum-docs-for = (doctype, top-posts-fun) ~>
    forum = {forums: [forum-tree(forum-id, top-posts-fun)], menu}
    @put-doc site-id, "forum_#{doctype}", forum-id, JSON.stringify(forum)
    posts = top-posts-fun(forum-id)
    @put-doc site-id, "threads_#{doctype}", forum-id, JSON.stringify(posts)

  build-forum-docs-for \recent, top-posts-recent!
  build-forum-docs-for \active, top-posts-active!
  true

export build-homepage-doc = (site-id) ->
  menu = @menu(site-id)

  build-homepage-doc-for = (doctype, top-posts-fun, top-forums-fun) ~>
    forums = forums-tree(site-id, top-posts-fun, top-forums-fun)
    homepage = {forums, menu}
    @put-doc site-id, doctype, site-id, JSON.stringify(homepage)

  build-homepage-doc-for \homepage_recent, top-posts-recent(5), top-forums-recent!
  build-homepage-doc-for \homepage_active, top-posts-active(5), top-forums-active!
  true

