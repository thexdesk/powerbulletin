jade=function(e){function t(e){return e!=null}return Array.isArray||(Array.isArray=function(e){return"[object Array]"==Object.prototype.toString.call(e)}),Object.keys||(Object.keys=function(e){var t=[];for(var n in e)e.hasOwnProperty(n)&&t.push(n);return t}),e.merge=function(n,r){var i=n["class"],s=r["class"];if(i||s)i=i||[],s=s||[],Array.isArray(i)||(i=[i]),Array.isArray(s)||(s=[s]),i=i.filter(t),s=s.filter(t),n["class"]=i.concat(s).join(" ");for(var o in r)o!="class"&&(n[o]=r[o]);return n},e.attrs=function(n,r){var i=[],s=n.terse;delete n.terse;var o=Object.keys(n),u=o.length;if(u){i.push("");for(var a=0;a<u;++a){var f=o[a],l=n[f];"boolean"==typeof l||null==l?l&&(s?i.push(f):i.push(f+'="'+f+'"')):0==f.indexOf("data")&&"string"!=typeof l?i.push(f+"='"+JSON.stringify(l)+"'"):"class"==f&&Array.isArray(l)?i.push(f+'="'+e.escape(l.join(" "))+'"'):r&&r[f]?i.push(f+'="'+e.escape(l)+'"'):i.push(f+'="'+l+'"')}}return i.join(" ")},e.escape=function(t){return String(t).replace(/&(?!(\w+|\#\d+);)/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;")},e.rethrow=function(t,n,r){if(!n)throw t;var i=3,s=require("fs").readFileSync(n,"utf8"),o=s.split("\n"),u=Math.max(r-i,0),a=Math.min(o.length,r+i),i=o.slice(u,a).map(function(e,t){var n=t+u+1;return(n==r?"  > ":"    ")+n+"| "+e}).join("\n");throw t.path=n,t.message=(n||"Jade")+":"+r+"\n"+i+"\n\n"+t.message,t},e}({}),jade.templates={},jade.render=function(e,t,n){var r=jade.templates[t](n);e.innerHTML=r},jade.templates.homepage=function(locals,attrs,escape,rethrow,merge){attrs=attrs||jade.attrs,escape=escape||jade.escape,rethrow=rethrow||jade.rethrow,merge=merge||jade.merge;var buf=[];with(locals||{}){var interp,forum_mixin=function(e,t){var n=this.block,r=this.attributes||{},i=this.escaped||{};buf.push("<img"),buf.push(attrs({id:"forum_bg_"+e.id+"",src:""+cache_url+"/images/bg_"+e.id+".jpg","class":"bg"},{id:!0,src:!0})),buf.push("/><a"),buf.push(attrs({name:"forum_"+e.id+""},{name:!0})),buf.push("></a><div"),buf.push(attrs({id:"forum_"+e.id+"","class":"forum "+(""+e.theme+" "+(t%2?"odd":"even")+"")},{"class":!0,id:!0})),buf.push('><div class="header"><div class="description">');var s=e.description;buf.push(escape(null==s?"":s)),buf.push('</div></div><div class="container">'),e.posts&&(function(){if("number"==typeof e.posts.length)for(var t=0,n=e.posts.length;t<n;t++){var r=e.posts[t];post_mixin(e,r,t)}else for(var t in e.posts){var r=e.posts[t];post_mixin(e,r,t)}}.call(this),buf.push("<div"),buf.push(attrs({"data-scroll-to":"#forum_"+e.id+"",title:"Scroll top of "+e.title+"!","class":"up scroll-to"},{"class":!0,"data-scroll-to":!0,title:!0})),buf.push("></div>")),buf.push("</div></div>")},post_mixin=function(e,t,n){var r=this.block,i=this.attributes||{},s=this.escaped||{};buf.push("<div"),buf.push(attrs({id:"post_"+t.id+"","class":"post "+("col"+Math.ceil(Math.random()*2)+"")},{"class":!0,id:!0})),buf.push("><a"),buf.push(attrs({href:e.slug,"class":"mutant"},{href:!0,"class":!0})),buf.push('><h5 class="title">');var o=t.title;buf.push(escape(null==o?"":o)),buf.push('<span class="date">'+escape((interp=t.date)==null?"":interp)+'</span></h5></a><p class="body">');var o=t.body;buf.push(escape(null==o?"":o)),buf.push("</p>"),t.posts&&function(){if("number"==typeof t.posts.length)for(var e=0,n=t.posts.length;e<n;e++){var r=t.posts[e];subpost_mixin(r,e)}else for(var e in t.posts){var r=t.posts[e];subpost_mixin(r,e)}}.call(this),buf.push('<div class="comment"><div class="photo"><img'),buf.push(attrs({src:""+cache_url+"/images/profile.jpg"},{src:!0})),buf.push('/></div><input type="text" placeholder="Say it ..." class="msg"/></div></div>')},subpost_mixin=function(e,t){var n=this.block,r=this.attributes||{},i=this.escaped||{};buf.push("<div"),buf.push(attrs({id:"subpost_"+e.id+"","class":"subpost "+(t%2?"odd":"even")},{"class":!0,id:!0})),buf.push('><div class="photo"><img'),buf.push(attrs({src:""+cache_url+"/images/profile.jpg"},{src:!0})),buf.push('/></div><p class="body">');var s=e.body;buf.push(escape(null==s?"":s)),buf.push('</p><div class="signature"><span class="username">- '+escape((interp=e.user.name)==null?"":interp)+'</span><span class="date">');var s=e.date;buf.push(escape(null==s?"":s)),buf.push("</span></div></div>")};forums?function(){if("number"==typeof forums.length)for(var e=0,t=forums.length;e<t;e++){var n=forums[e];forum_mixin(n,e)}else for(var e in forums){var n=forums[e];forum_mixin(n,e)}}.call(this):buf.push("<p>Create a forum first<i>!</i></p>")}return buf.join("")},jade.templates.nav=function(locals,attrs,escape,rethrow,merge){attrs=attrs||jade.attrs,escape=escape||jade.escape,rethrow=rethrow||jade.rethrow,merge=merge||jade.merge;var buf=[];with(locals||{}){var interp,forum_mixin=function(e,t){var n=this.block,r=this.attributes||{},i=this.escaped||{};buf.push("<a"),buf.push(attrs({href:e.slug},{href:!0})),buf.push(">");var s=e.title;buf.push(escape(null==s?"":s)),buf.push("</a>"),e.subforums&&function(){if("number"==typeof e.subforums.length)for(var t=0,n=e.subforums.length;t<n;t++){var r=e.subforums[t];subforum_mixin(r,e,t)}else for(var t in e.subforums){var r=e.subforums[t];subforum_mixin(r,e,t)}}.call(this)},subforum_mixin=function(e,t){var n=this.block,r=this.attributes||{},i=this.escaped||{};buf.push("<div"),buf.push(attrs({id:"subforum_"+e.id+"","class":"subforum "+(t%2?"odd":"even")},{"class":!0,id:!0})),buf.push('><span class="title">');var s=e.title;buf.push(escape(null==s?"":s)),buf.push("</span></div>")};forums&&function(){if("number"==typeof forums.length)for(var e=0,t=forums.length;e<t;e++){var n=forums[e];forum_mixin(n,e)}else for(var e in forums){var n=forums[e];forum_mixin(n,e)}}.call(this)}return buf.join("")},jade.templates.posts=function(locals,attrs,escape,rethrow,merge){attrs=attrs||jade.attrs,escape=escape||jade.escape,rethrow=rethrow||jade.rethrow,merge=merge||jade.merge;var buf=[];with(locals||{}){var interp,post_mixin=function(e,t){var n=this.block,r=this.attributes||{},i=this.escaped||{};buf.push("<a"),buf.push(attrs({href:e.slug},{href:!0})),buf.push(">");var s=e.title;buf.push(escape(null==s?"":s)),buf.push("</a>"),function(){if("number"==typeof e.subposts.length)for(var t=0,n=e.subposts.length;t<n;t++){var r=e.subposts[t];subpost_mixin(e,r,t)}else for(var t in e.subposts){var r=e.subposts[t];subpost_mixin(e,r,t)}}.call(this)},subpost_mixin=function(e,t,n){var r=this.block,i=this.attributes||{},s=this.escaped||{};buf.push("<div"),buf.push(attrs({id:"subpost"+t.id+"","class":"subpost "+(n%2?"odd":"even")},{"class":!0,id:!0})),buf.push('><h4 class="title">');var o=t.title;buf.push(escape(null==o?"":o)),buf.push('</h4><div class="user">');var o=t.user.name;buf.push(escape(null==o?"":o)),buf.push('</div><div class="date">');var o=t.date;buf.push(escape(null==o?"":o)),buf.push('</div><p class="body">');var o=t.body;buf.push(escape(null==o?"":o)),buf.push("</p></div>")};forums&&function(){if("number"==typeof forums.length)for(var e=0,t=forums.length;e<t;e++){var n=forums[e];(function(){if("number"==typeof n.posts.length)for(var e=0,t=n.posts.length;e<t;e++){var r=n.posts[e];post_mixin(r,e)}else for(var e in n.posts){var r=n.posts[e];post_mixin(r,e)}}).call(this)}else for(var e in forums){var n=forums[e];(function(){if("number"==typeof n.posts.length)for(var e=0,t=n.posts.length;e<t;e++){var r=n.posts[e];post_mixin(r,e)}else for(var e in n.posts){var r=n.posts[e];post_mixin(r,e)}}).call(this)}}.call(this)}return buf.join("")}