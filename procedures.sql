DROP SCHEMA IF EXISTS procs CASCADE;
CREATE SCHEMA procs;

CREATE FUNCTION procs.find_or_create(sel JSON, sel_params JSON, ins JSON, ins_params JSON) RETURNS JSON AS $$
  thing = plv8.execute(sel, sel_params)
  return thing[0] if thing.length > 0
  plv8.execute(ins, ins_params)
  return plv8.execute(sel, sel_params)[0]
$$ LANGUAGE plls IMMUTABLE STRICT;

-- Posts {{{
CREATE FUNCTION procs.owns_post(post_id JSON, user_id JSON) RETURNS JSON AS $$
  return plv8.execute('SELECT id FROM posts WHERE id=$1 AND user_id=$2', [post_id, user_id])
$$ LANGUAGE plls IMMUTABLE STRICT;

CREATE FUNCTION procs.post(id JSON) RETURNS JSON AS $$
  sql = '''
  SELECT p.*,
  a.name AS user_name ,
  u.photo AS user_photo,
  (SELECT COUNT(*) FROM posts WHERE parent_id = p.id) AS post_count,
  ARRAY(SELECT tags.name FROM tags JOIN tags_posts ON tags.id = tags_posts.tag_id WHERE tags_posts.post_id = p.id) AS tags
  FROM posts p
  JOIN users u ON p.user_id = u.id
  JOIN aliases a ON u.id = a.user_id
  WHERE p.id = $1;
  '''
  return plv8.execute(sql, [id])?0
$$ LANGUAGE plls IMMUTABLE STRICT;

CREATE FUNCTION procs.posts_by_user(usr JSON, page JSON, ppp JSON) RETURNS JSON AS $$
  require! \prelude
  sql = '''
  SELECT
  p.*,
  a.name AS user_name ,
  u.photo AS user_photo,
  (SELECT COUNT(*) FROM posts WHERE parent_id = p.id) AS post_count
  FROM posts p
  JOIN users u ON p.user_id = u.id
  JOIN aliases a ON u.id = a.user_id
  WHERE p.forum_id IN (SELECT id FROM forums WHERE site_id = $1)
  AND a.name = $2
  ORDER BY p.created DESC
  LIMIT  $3
  OFFSET $4
  '''
  offset = (page - 1) * ppp
  posts = plv8.execute(sql, [usr.site_id, usr.name, ppp, offset])

  if posts.length
    # fetch thread & forum context
    thread-sql = """
      SELECT p.id,p.title,p.uri, a.user_id,a.name, f.uri furi,f.title ftitle
      FROM posts p
        LEFT JOIN aliases a ON a.user_id=p.user_id
        LEFT JOIN posts f ON f.id=p.forum_id
      WHERE p.id IN (#{(prelude.unique [p.thread_id for p,i in posts]).join(', ')})
    """
    ctx = plv8.execute(thread-sql, [])

    # hash for o(n) + o(1) * posts -> thread mapping
    lookup = {[v.id, v] for k,v of ctx}
    for p in posts
      t = lookup[p.thread_id] # thread
      [p.thread_uri, p.thread_title, p.thread_username, p.forum_uri, p.forum_title] =
        [t.uri, t.title, t.name, t.furi, t.ftitle]

  return posts
$$ LANGUAGE plls IMMUTABLE STRICT;

CREATE FUNCTION procs.posts_by_user_pages_count(usr JSON, ppp JSON) RETURNS JSON AS $$
  sql = '''
  SELECT
  COUNT(p.id) as c
  FROM posts p
  JOIN users u ON p.user_id = u.id
  JOIN aliases a ON u.id = a.user_id
  WHERE p.forum_id IN (SELECT id FROM forums WHERE site_id = $1)
  AND a.name = $2
  '''
  res   = plv8.execute(sql, [usr.site_id, usr.name])
  c     = res[0]?c or 0
  pages = Math.ceil(c / ppp)
  return pages
$$ LANGUAGE plls IMMUTABLE STRICT;

CREATE FUNCTION procs.edit_post(usr JSON, post JSON) RETURNS JSON AS $$
  require! <[u validations]>
  errors = validations.post(post)

  # check ownership & access
  fn = plv8.find_function('procs.owns_post')
  r = fn(post.id, usr.id)
  errors.push "Higher access required" unless r.length
  unless errors.length
    return plv8.execute('UPDATE posts SET title=$1,body=$2,html=$3 WHERE id=$4 RETURNING id,title,body,forum_id', [post.title, post.body, post.html, post.id])
  return {success: !errors.length, errors}
$$ LANGUAGE plls IMMUTABLE STRICT;

-- THIS IS ONLY FOR TOPLEVEL POSTS
-- TODO: needs to support nested posts also, and update correct thread-id
-- @param Object post
--   @param Number forum_id
--   @param Number user_id
--   @param String title
--   @param String body
--   @param String html
-- @returns Object
CREATE FUNCTION procs.add_post(post JSON) RETURNS JSON AS $$
  var uri
  require! <[u validations]>
  errors = validations.post(post)
  if !errors.length
    if site-id = plv8.execute('SELECT site_id FROM forums WHERE id=$1', [post.forum_id])[0]?.site_id
      [{nextval}] = plv8.execute("SELECT nextval('posts_id_seq')", [])

      forum-id = parse-int(post.forum_id) or null
      parent-id = parse-int(post.parent_id) or null
      if post.parent_id
        r = plv8.execute('SELECT thread_id FROM posts WHERE id=$1', [post.parent_id])
        unless thread_id = r.0?thread_id
          errors.push 'Invalid thread ID'; return {success: !errors.length, errors}
        # child posts use id for slug
        # XXX: todo flatten this into a hash or singular id in the uri instead of nesting subcomments
        slug = nextval
      else
        thread_id = nextval
        # top-level posts use title text for generating a slug
        slug = u.title2slug(post.title) # try pretty version first

      # TODO: don't use numeric identifier in slug unless you have to, use subtransaction to catch the case and use the more-unique version
      # TODO: kill comment url recursions and go flat with the threads side of things (hashtag like reddit?) or keep it the same
      #       its a question of url length

      sql = '''
      INSERT INTO posts (id, thread_id, user_id, forum_id, parent_id, title, slug, body, html, ip)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
      '''

      params =
        * nextval
        * thread_id
        * parse-int(post.user_id) or null
        * forum-id
        * parent-id
        * post.title
        * slug
        * post.body || ""
        * post.html || ""
        * post.ip

      plv8.execute(sql, params)

      # the post must be inserted before uri-for-post will work, thats why uri is a NULLABLE column
      try
        plv8.subtransaction ->
          uri := u.uri-for-post(nextval)
          plv8.execute 'UPDATE posts SET uri=$1 WHERE id=$2', [uri, nextval]
      catch
        slug = u.title2slug(post.title, nextval) # add uniqueness since there is one which exists already
        plv8.execute 'UPDATE posts SET slug=$1 WHERE id=$2', [slug, nextval]
        uri := u.uri-for-post(nextval)
        plv8.execute 'UPDATE posts SET uri=$1 WHERE id=$2', [uri, nextval]

      # associate tags to post
      if post.tags
        add-tags-to-post = plv8.find_function('procs.add_tags_to_post')
        add-tags-to-post nextval, post.tags

    else
      errors.push "forum_id invalid: #{post.forum_id}"

  return {success: !errors.length, errors, id: nextval, uri}
$$ LANGUAGE plls IMMUTABLE STRICT;

-- Add tags to system
-- @param   Array  tags    an array of tags as strings
-- @returns Array          an array of tag objects
CREATE FUNCTION procs.add_tags(tags JSON) RETURNS JSON AS $$
  add-tag = (tag) ->
    sql = '''
    INSERT INTO tags (name) SELECT $1::varchar WHERE NOT EXISTS (SELECT name FROM tags WHERE name = $1) RETURNING *
    '''
    res = plv8.execute sql, [tag]
    if res.length == 0
      res2 = plv8.execute 'SELECT * FROM tags WHERE name = $1', [tag]
      return res2[0]
    else
      return res[0]
  return [ add-tag t for t in tags ]
$$ LANGUAGE plls IMMUTABLE STRICT;

-- Associate tags to a post
-- @param   Number post_id
-- @param   Array  tags    an array of tags as strings
-- @returns Array          an array of tag objects
CREATE FUNCTION procs.add_tags_to_post(post_id JSON, tags JSON) RETURNS JSON AS $$
  require! \prelude
  if not tags or tags.length == 0 then return null
  unique-tags = prelude.unique tags
  add-tags    = plv8.find_function('procs.add_tags')
  added-tags  = add-tags unique-tags
  sql         = 'INSERT INTO tags_posts (tag_id, post_id) VALUES ' + (["($#{parse-int(i)+2}, $1)" for v,i in added-tags]).join(', ')
  params      = [post_id, ...(prelude.map (.id), added-tags)]
  res         = plv8.execute sql, params
  plv8.elog WARNING, "add-tags-to-post -> #{JSON.stringify({res, params})}"
  return added-tags
$$ LANGUAGE plls IMMUTABLE STRICT;

CREATE FUNCTION procs.archive_post(post_id JSON) RETURNS JSON AS $$
  require! u
  [{forum_id}] = plv8.execute "SELECT forum_id FROM posts WHERE id=$1", [post_id]
  [{site_id}] = plv8.execute 'SELECT site_id FROM forums WHERE forum_id=$1', [forum_id]
  plv8.execute "UPDATE posts SET archived='t' WHERE id=$1", [post_id]
  return true
$$ LANGUAGE plls IMMUTABLE STRICT;

CREATE FUNCTION procs.sub_posts_tree(site_id JSON, post_id JSON, lim JSON, oft JSON) RETURNS JSON AS $$
  require! u
  return u.sub-posts-tree site_id, post_id, lim, oft
$$ LANGUAGE plls IMMUTABLE STRICT;
--}}}
-- Users & Aliases {{{

-- Find a user by auths.type and auths.id
-- However, more information should be provided in case a new user needs to be created.
-- @param Object usr
--   @param String type         auths.type (facebook|google|twitter|local)
--   @param Number id           auths.id (3rd party user id)
--   @param JSON   profile      auths.profile (3rd party profile object)
--   @param Number site_id      aliases.site_id
--   @param String name         aliases.name
--   @param String verify       aliases.verify
CREATE FUNCTION procs.find_or_create_user(usr JSON) RETURNS JSON AS $$
  sel = '''
  SELECT u.id, u.created, a.site_id, a.name, auths.type, auths.profile
  FROM users u
    LEFT JOIN aliases a ON a.user_id = u.id
    LEFT JOIN auths ON auths.user_id = u.id
  WHERE auths.type = $1
  AND auths.id = $2
  '''
  sel-params =
    * usr.type
    * usr.id

  ins = '''
  WITH u AS (
      INSERT INTO users DEFAULT VALUES
        RETURNING id
    ), a AS (
      INSERT INTO auths (id, user_id, type, profile)
        SELECT $1::decimal, u.id, $2::varchar, $3::json FROM u
        RETURNING *
    )
  INSERT INTO aliases (user_id, site_id, name, verify)
    SELECT u.id, $4::bigint, $5::varchar, $6::varchar FROM u;
  '''
  ins-params =
    * usr.id
    * usr.type
    * JSON.stringify(usr.profile)
    * usr.site_id
    * usr.name
    * usr.verify

  find-or-create = plv8.find_function('procs.find_or_create')
  return find-or-create(sel, sel-params, ins, ins-params)
$$ LANGUAGE plls IMMUTABLE STRICT;

-- register_local_user(usr)
--
-- Find a user by auths.type and auths.id
-- However, more information should be provided in case a new user needs to be created.
-- @param Object usr
--   @param String type         auths.type (facebook|google|twitter|local)
--   @param Number id           auths.id (3rd party user id)
--   @param JSON   profile      auths.profile (3rd party profile object)
--   @param Number site_id      aliases.site_id
--   @param String name         aliases.name
--   @param String verify       aliases.verify
CREATE FUNCTION procs.register_local_user(usr JSON) RETURNS JSON AS $$
  ins = '''
  WITH u AS (
      INSERT INTO users (email) VALUES ($1)
        RETURNING id
    ), a AS (
      INSERT INTO auths (id, user_id, type, profile)
        SELECT u.id, u.id, $2::varchar, $3::json FROM u
        RETURNING *
    )
  INSERT INTO aliases (user_id, site_id, name, verify)
    SELECT u.id, $4::bigint, $5::varchar, $6::varchar FROM u;
  '''
  ins-params =
    * usr.email
    * usr.type
    * JSON.stringify(usr.profile)
    * usr.site_id
    * usr.name
    * usr.verify
  return plv8.execute ins, ins-params
$$ LANGUAGE plls IMMUTABLE STRICT;

-- XXX - need site_id
CREATE FUNCTION procs.unique_name(usr JSON) RETURNS JSON AS $$
  sql = '''
  SELECT name FROM aliases WHERE name=$1 AND site_id=$2
  '''
  [n,i]=[usr.name,0]
  while plv8.execute(sql, [n, usr.site_id])[0]
    n="#{usr.name}#{++i}"
  return JSON.stringify n # XXX why stringify??!
$$ LANGUAGE plls IMMUTABLE STRICT;

CREATE FUNCTION procs.name_exists(usr JSON) RETURNS JSON AS $$
  sql = '''
  SELECT user_id, name FROM aliases WHERE name = $1 and site_id = $2
  '''
  r = plv8.execute sql, [usr.name, usr.site_id]
  if !!r.length
    return r[0].user_id
  else
    return 0 # relying on 0 to be false
$$ LANGUAGE plls IMMUTABLE STRICT;

-- change alias
CREATE FUNCTION procs.change_alias(usr JSON) RETURNS JSON AS $$
  sql = '''
  UPDATE aliases SET name = $1 WHERE user_id = $2 AND site_id = $3
    RETURNING *
  '''
  return plv8.execute(sql, [usr.name, usr.user_id, usr.site_id])
$$ LANGUAGE plls IMMUTABLE STRICT;

-- change avatar
CREATE FUNCTION procs.change_avatar(usr JSON, path JSON) RETURNS JSON AS $$
  sql = '''
  UPDATE users SET photo = $1 WHERE id = $2
    RETURNING *
  '''
  return plv8.execute(sql, [path, usr.id])
$$ LANGUAGE plls IMMUTABLE STRICT;

-- find an alias by site_id and verify string
CREATE FUNCTION procs.alias_by_verify(site_id JSON, verify JSON) RETURNS JSON AS $$
  sql = '''
  SELECT * FROM aliases WHERE site_id = $1 AND verify = $2
  '''
  return plv8.execute(sql, [site_id, verify])[0]
$$ LANGUAGE plls IMMUTABLE STRICT;

--
CREATE FUNCTION procs.verify_user(site_id JSON, verify JSON) RETURNS JSON AS $$
  sql = '''
  UPDATE aliases SET verified = true WHERE site_id = $1 AND verify = $2 RETURNING *
  '''
  return plv8.execute(sql, [site_id, verify])[0]
$$ LANGUAGE plls IMMUTABLE STRICT;

-- @param Object usr
--   @param String  name       user name
--   @param Integer site_id    site id
-- @returns Object user        user with all auth objects
CREATE FUNCTION procs.usr(usr JSON) RETURNS JSON AS $$
  [identifier-clause, params] =
    if usr.id
      ["u.id = $1", [usr.id, usr.site_id]]
    else
      ["a.name = $1", [usr.name, usr.site_id]]

  sql = """
  SELECT
    u.id, u.photo, u.email,
    a.rights, a.name, a.created, a.site_id,
    (SELECT COUNT(*) FROM posts WHERE user_id = u.id AND site_id = $2) AS post_count,
    auths.type, auths.profile 
  FROM users u
  JOIN aliases a ON a.user_id = u.id
  LEFT JOIN auths ON auths.user_id = u.id
  WHERE #identifier-clause
  AND a.site_id = $2
  """
  auths = plv8.execute(sql, params)
  if auths.length == 0
    return null
  make-user = (memo, auth) ->
    memo.auths[auth.type] = auth.profile
    memo
  u =
    auths      : {}
    id         : auths.0?id
    site_id    : auths.0?site_id
    name       : auths.0?name
    photo      : auths.0?photo
    email      : auths.0?email
    rights     : auths.0?rights
    created    : auths.0?created
    post_count : auths.0?post_count
  user = auths.reduce make-user, u
  return user
$$ LANGUAGE plls IMMUTABLE STRICT;
--}}}
-- {{{ Sites & Domains
-- @param String domain
CREATE FUNCTION procs.site_by_domain(domain JSON) RETURNS JSON AS $$
  sql = """
  SELECT s.*, d.name AS domain
  FROM sites s JOIN domains d ON s.id = d.site_id
  WHERE d.name = $1
  """
  s = plv8.execute(sql, [ domain ])
  return s[0]
$$ LANGUAGE plls IMMUTABLE STRICT;

-- @param Integer id
CREATE FUNCTION procs.site_by_id(id JSON) RETURNS JSON AS $$
  sql = """
  SELECT s.*, d.name AS domain
  FROM sites s JOIN domains d ON s.id = d.site_id
  WHERE s.id = $1
  """
  s = plv8.execute(sql, [ id ])
  return s[0]
$$ LANGUAGE plls IMMUTABLE STRICT;

CREATE FUNCTION procs.update_site(site JSON) RETURNS JSON AS $$
  sql = """
  UPDATE sites SET name = $1, config = $2, user_id = $3 WHERE id = $4
    RETURNING *
  """
  s = plv8.execute(sql, [ site.name, site.config, site.user_id, site.id ])
  return s[0]
$$ LANGUAGE plls IMMUTABLE STRICT;

CREATE FUNCTION procs.domains() RETURNS JSON AS $$
  sql = """
  SELECT name FROM domains
  """
  return plv8.execute(sql).map (d) -> d.name
$$ LANGUAGE plls IMMUTABLE STRICT;

-- }}}
-- {{{ Forums & Threads
CREATE FUNCTION procs.add_thread_impression(thread_id JSON) RETURNS JSON AS $$
  if not thread_id or thread_id is \undefined
    return false
  sql = '''
  UPDATE posts SET views = views + 1 WHERE id = $1 RETURNING *
  '''
  res = plv8.execute sql, [thread_id]
  return res[0]
$$ LANGUAGE plls IMMUTABLE STRICT;

CREATE FUNCTION procs.build_all_uris(site_id JSON) RETURNS JSON AS $$
  require! u
  forums = plv8.execute 'SELECT id FROM forums WHERE site_id=$1', [site_id]
  posts = plv8.execute 'SELECT p.id FROM posts p JOIN forums f ON f.id=forum_id WHERE f.site_id=$1', [site_id]

  for f in forums
    uri = u.uri-for-forum(f.id)
    plv8.execute 'UPDATE forums SET uri=$1 WHERE id=$2', [uri, f.id]

  for p in posts
    uri = u.uri-for-post(p.id)
    plv8.execute 'UPDATE posts SET uri=$1 WHERE id=$2', [uri, p.id]

  return true
$$ LANGUAGE plls IMMUTABLE STRICT;

CREATE FUNCTION procs.ban_patterns_for_forum(forum_id JSON) RETURNS JSON AS $$
  if f = plv8.execute('SELECT parent_id, uri FROM forums WHERE id=$1', [forum_id])[0]
    bans = []
    bans.push '^/$' unless f.parent_id # sub-forums need not ban the homepage.. maybe??
    bans.push "^#{f.uri}" # anything that beings with forum uri
    return bans
  else
    return []
$$ LANGUAGE plls IMMUTABLE STRICT;

CREATE FUNCTION procs.menu(site_id JSON) RETURNS JSON AS $$
  require! u
  return u.menu site_id
$$ LANGUAGE plls IMMUTABLE STRICT;

CREATE FUNCTION procs.homepage_forums(forum_id JSON, sort JSON) RETURNS JSON AS $$
  require! u
  return u.homepage-forums forum_id, sort
$$ LANGUAGE plls IMMUTABLE STRICT;

CREATE FUNCTION procs.forum_summary(forum_id JSON, thread_limit JSON, post_limit JSON) RETURNS JSON AS $$
  require! u
  tpf = u.top-posts(\recent, thread_limit)
  latest-threads = tpf(forum_id)

  forumf = plv8.find_function('procs.forum')
  forum = forumf(forum_id)

  # This query can be moved into its own proc and generalized so that it can
  # provide a flat view of a thread.
  sql = """
  SELECT
    p.*,
    a.name user_name,
    u.photo user_photo
  FROM posts p
  JOIN aliases a ON a.user_id = p.user_id
  JOIN users u ON u.id = a.user_id
  JOIN forums f ON f.id = p.forum_id
  JOIN sites s ON s.id = f.site_id
  LEFT JOIN moderations m ON m.post_id = p.id
  WHERE a.site_id = s.id
    AND p.thread_id = $1
    AND p.parent_id IS NOT NULL
  ORDER BY p.created DESC
  LIMIT $2
  """
  forum.posts = [ (t.posts = plv8.execute(sql, [t.id, post_limit])) and t for t in latest-threads ]
  return [forum]
$$ LANGUAGE plls IMMUTABLE STRICT;

CREATE FUNCTION procs.top_threads(forum_id JSON, s JSON) RETURNS JSON AS $$
  require! u
  return u.top-threads forum_id, s
$$ LANGUAGE plls IMMUTABLE STRICT;

CREATE FUNCTION procs.uri_to_forum_id(site_id JSON, uri JSON) RETURNS JSON AS $$
  require! u
  try
    [{id}] = plv8.execute 'SELECT id FROM forums WHERE site_id=$1 AND uri=$2', [site_id, uri]
    return id
  catch
    return null
$$ LANGUAGE plls IMMUTABLE STRICT;

CREATE FUNCTION procs.forum(id JSON) RETURNS JSON AS $$
  return plv8.execute('SELECT * FROM forums WHERE id=$1', [id])[0]
$$ LANGUAGE plls IMMUTABLE STRICT;

CREATE FUNCTION procs.uri_to_post(site_id JSON, uri JSON) RETURNS JSON AS $$
  require! u
  try
    sql = '''
    SELECT p.*, u.photo user_photo, a.name user_name
    FROM posts p
    JOIN forums f ON p.forum_id=f.id
    LEFT JOIN moderations m ON m.post_id=p.id
    JOIN users u ON p.user_id=u.id
    JOIN aliases a ON a.user_id=u.id
    WHERE f.site_id=$1
      AND p.uri=$2
      AND m.post_id IS NULL
    '''
    [post] = plv8.execute sql, [site_id, uri]
    return post
  catch
    return null
$$ LANGUAGE plls IMMUTABLE STRICT;

-- c is for 'command'
CREATE FUNCTION procs.censor(c JSON) RETURNS JSON AS $$
  require! {u, validations}

  sql = '''
  INSERT INTO moderations (user_id, post_id, reason)
  VALUES ($1, $2, $3)
  '''

  errors = validations.censor(c)

  if !errors.length
    plv8.execute sql, [c.user_id, c.post_id, c.reason]

  return {success: !errors.length, errors}
$$ LANGUAGE plls IMMUTABLE STRICT;

CREATE FUNCTION procs.sub_posts_count(parent_id JSON) RETURNS JSON AS $$
  sql = '''
  SELECT COUNT(*)
  FROM posts p
  LEFT JOIN moderations m ON m.post_id=p.id
  WHERE p.parent_id=$1
    AND m.post_id IS NULL
  '''
  [{count}] = plv8.execute sql, [parent_id]
  return count
$$ LANGUAGE plls IMMUTABLE STRICT;

CREATE FUNCTION procs.idx_posts(lim JSON) RETURNS JSON AS $$
  sql = '''
  SELECT id, title, body, user_id, created, updated
  FROM posts
  WHERE index_dirty='t'
  ORDER BY updated
  LIMIT $1
  '''
  return plv8.execute sql, [lim]
$$ LANGUAGE plls IMMUTABLE STRICT;

-- acknowledge / flag the post as indexed so we don't try to index it again
CREATE FUNCTION procs.idx_ack_post(post_id JSON) RETURNS JSON AS $$
  sql = '''
  UPDATE posts SET index_dirty='f' WHERE id=$1
  '''
  plv8.execute sql, [post_id]
  return true
$$ LANGUAGE plls IMMUTABLE STRICT;
--}}}
-- vim:fdm=marker
