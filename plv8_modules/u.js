(function(){
  var merge, title2slug, topForums, subForums, topPosts, subPosts, subPostsTree, postsTree, decorateMenu, decorateForum, doc, putDoc, forumTree, forumsTree, uriForForum, uriForPost, menu, homepageForums, forums, topThreads, out$ = typeof exports != 'undefined' && exports || this, slice$ = [].slice;
  out$.merge = merge = merge = function(){
    var args, r;
    args = slice$.call(arguments);
    r = function(rval, hval){
      return import$(rval, hval);
    };
    return args.reduce(r, {});
  };
  out$.title2slug = title2slug = function(title, id){
    title = title.toLowerCase();
    title = title.replace(new RegExp('[^a-z0-9 ]', 'g'), '');
    title = title.replace(new RegExp(' +', 'g'), '-');
    title = title.slice(0, 30);
    if (id) {
      title = title.concat("-" + id);
    }
    return title;
  };
  topForums = function(limit, fields){
    var sql;
    fields == null && (fields = '*');
    sql = "SELECT " + fields + " FROM forums\nWHERE parent_id IS NULL AND site_id=$1\nORDER BY created DESC, id ASC\nLIMIT $2";
    return function(){
      var args;
      args = slice$.call(arguments);
      return plv8.execute(sql, args.concat([limit]));
    };
  };
  subForums = function(id, fields){
    var sql;
    fields == null && (fields = '*');
    sql = "SELECT " + fields + "\nFROM forums\nWHERE parent_id=$1\nORDER BY created DESC, id DESC";
    return plv8.execute(sql, [id]);
  };
  topPosts = function(sort, limit, fields){
    var sortExpr, sql;
    fields == null && (fields = 'p.*');
    sortExpr = (function(){
      switch (sort) {
      case 'recent':
        return 'p.created DESC, id ASC';
      case 'popular':
        return '(SELECT (SUM(views) + COUNT(*)*2) FROM posts WHERE thread_id=p.thread_id GROUP BY thread_id) DESC';
      default:
        throw new Error("invalid sort for top-posts: " + sort);
      }
    }());
    sql = "SELECT\n  " + fields + ",\n  MIN(a.name) user_name,\n  MIN(u.photo) user_photo,\n  COUNT(p2.id) post_count\nFROM aliases a\nJOIN posts p ON a.user_id=p.user_id\nJOIN users u ON u.id=a.user_id\nLEFT JOIN posts p2 ON p2.parent_id=p.id\nLEFT JOIN moderations m ON m.post_id=p.id\nWHERE a.site_id=1\n  AND p.parent_id IS NULL\n  AND p.forum_id=$1\n  AND m.post_id IS NULL\nGROUP BY p.id\nORDER BY " + sortExpr + "\nLIMIT $2";
    return function(){
      var args;
      args = slice$.call(arguments);
      return plv8.execute(sql, args.concat([limit]));
    };
  };
  subPosts = function(siteId, postId, limit, offset){
    var sql;
    sql = 'SELECT p.*, a.name user_name, u.photo user_photo\nFROM posts p\nJOIN aliases a ON a.user_id=p.user_id\nJOIN users u ON u.id=a.user_id\nLEFT JOIN moderations m ON m.post_id=p.id\nWHERE a.site_id=$1\n  AND p.parent_id=$2\n  AND m.post_id IS NULL\nORDER BY created ASC, id ASC\nLIMIT $3 OFFSET $4';
    return plv8.execute(sql, [siteId, postId, limit, offset]);
  };
  out$.subPostsTree = subPostsTree = subPostsTree = function(siteId, parentId, limit, offset, depth){
    var sp, i$, len$, p, results$ = [];
    depth == null && (depth = 3);
    sp = subPosts(siteId, parentId, limit, offset);
    if (depth <= 0) {
      for (i$ = 0, len$ = sp.length; i$ < len$; ++i$) {
        p = sp[i$];
        results$.push(merge(p, {
          posts: [],
          morePosts: !!subPosts(siteId, p.id, limit, 0).length
        }));
      }
      return results$;
    } else {
      for (i$ = 0, len$ = sp.length; i$ < len$; ++i$) {
        p = sp[i$];
        results$.push(merge(p, {
          posts: subPostsTree(siteId, p.id, limit, 0, depth - 1)
        }));
      }
      return results$;
    }
  };
  postsTree = function(siteId, forumId, topPosts){
    var i$, len$, p, results$ = [];
    for (i$ = 0, len$ = topPosts.length; i$ < len$; ++i$) {
      p = topPosts[i$];
      results$.push(merge(p, {
        posts: subPostsTree(siteId, p.id, 10, 0)
      }));
    }
    return results$;
  };
  decorateMenu = function(f){
    var sf;
    return merge(f, {
      forums: (function(){
        var i$, ref$, len$, results$ = [];
        for (i$ = 0, len$ = (ref$ = subForums(f.id, 'id,title,slug,uri,description,media_url')).length; i$ < len$; ++i$) {
          sf = ref$[i$];
          results$.push(decorateMenu(sf));
        }
        return results$;
      }())
    });
  };
  decorateForum = function(f, topPostsFun){
    var sf;
    return merge(f, {
      posts: postsTree(f.site_id, f.id, topPostsFun(f.id)),
      forums: (function(){
        var i$, ref$, len$, results$ = [];
        for (i$ = 0, len$ = (ref$ = subForums(f.id)).length; i$ < len$; ++i$) {
          sf = ref$[i$];
          results$.push(decorateForum(sf, topPostsFun));
        }
        return results$;
      }())
    });
  };
  out$.doc = doc = function(){
    var res;
    if (res = plv8.execute('SELECT json FROM docs WHERE site_id=$1 AND type=$2 AND key=$3', arguments)[0]) {
      return JSON.parse(res.json);
    } else {
      return null;
    }
  };
  out$.putDoc = putDoc = function(){
    var args, insertSql, updateSql, e;
    args = slice$.call(arguments);
    insertSql = 'INSERT INTO docs (site_id, type, key, json) VALUES ($1, $2, $3, $4)';
    updateSql = 'UPDATE docs SET json=$4 WHERE site_id=$1::bigint AND type=$2::varchar(64) AND key=$3::varchar(64)';
    if (args[3]) {
      args[3] = JSON.stringify(args[3]);
    }
    try {
      plv8.subtransaction(function(){
        return plv8.execute(insertSql, args);
      });
    } catch (e$) {
      e = e$;
      plv8.execute(updateSql, args);
    }
    return true;
  };
  forumTree = function(forumId, topPostsFun){
    var sql, f;
    sql = 'SELECT id,site_id,parent_id,title,slug,description,media_url,classes FROM forums WHERE id=$1 LIMIT 1';
    if (f = plv8.execute(sql, [forumId])[0]) {
      return decorateForum(f, topPostsFun);
    }
  };
  forumsTree = function(siteId, topPostsFun, topForumsFun){
    var i$, ref$, len$, f, results$ = [];
    for (i$ = 0, len$ = (ref$ = topForumsFun(siteId)).length; i$ < len$; ++i$) {
      f = ref$[i$];
      results$.push(decorateForum(f, topPostsFun));
    }
    return results$;
  };
  out$.uriForForum = uriForForum = function(forumId){
    var sql, ref$, parent_id, slug;
    sql = 'SELECT parent_id, slug FROM forums WHERE id=$1';
    ref$ = plv8.execute(sql, [forumId])[0], parent_id = ref$.parent_id, slug = ref$.slug;
    if (parent_id) {
      return this.uriForForum(parent_id) + '/' + slug;
    } else {
      return '/' + slug;
    }
  };
  out$.uriForPost = uriForPost = function(postId, firstSlug){
    var sql, ref$, forum_id, parent_id, slug;
    firstSlug == null && (firstSlug = null);
    sql = 'SELECT forum_id, parent_id, slug FROM posts WHERE id=$1';
    ref$ = plv8.execute(sql, [postId])[0], forum_id = ref$.forum_id, parent_id = ref$.parent_id, slug = ref$.slug;
    if (parent_id) {
      if (firstSlug) {
        return this.uriForPost(parent_id, firstSlug);
      } else {
        return this.uriForPost(parent_id, slug);
      }
    } else {
      if (firstSlug) {
        return this.uriForForum(forum_id) + '/t/' + slug + '/' + firstSlug;
      } else {
        return this.uriForForum(forum_id) + '/t/' + slug;
      }
    }
  };
  out$.menu = menu = function(siteId){
    var topMenuFun, i$, ref$, len$, f, results$ = [];
    topMenuFun = topForums(null, 'id,title,slug,uri,description,media_url');
    for (i$ = 0, len$ = (ref$ = topMenuFun(siteId)).length; i$ < len$; ++i$) {
      f = ref$[i$];
      results$.push(decorateMenu(f, topMenuFun));
    }
    return results$;
  };
  out$.homepageForums = homepageForums = function(siteId){
    return forumsTree(siteId, topPosts('recent', 10), topForums());
  };
  out$.forums = forums = function(forumId, sort){
    var ft;
    ft = forumTree(forumId, topPosts(sort));
    if (ft) {
      return [ft];
    } else {
      return [];
    }
  };
  out$.topThreads = topThreads = function(forumId, sort){
    return topPosts(sort)(forumId);
  };
  function import$(obj, src){
    var own = {}.hasOwnProperty;
    for (var key in src) if (own.call(src, key)) obj[key] = src[key];
    return obj;
  }
}).call(this);
