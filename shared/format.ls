define = window?define or require(\amdefine) module
require, exports, module <- define

require! {
  markdown
}
{id, is-type} = require \prelude-ls
md = if markdown.markdown then markdown.markdown else markdown

@util = util = {}

# A robust regexp for matching URLs. Thanks: https://gist.github.com/dperini/729294
#   via https://github.com/evilstreak/markdown-js/blob/master/src/dialects/gruber.js
url-pattern = /(?:(?:https?|ftp):\/\/)(?:\S+(?::\S*)?@)?(?:(?!10(?:\.\d{1,3}){3})(?!127(?:\.\d{1,3}){3})(?!169\.254(?:\.\d{1,3}){2})(?!192\.168(?:\.\d{1,3}){2})(?!172\.(?:1[6-9]|2\d|3[0-1])(?:\.\d{1,3}){2})(?:[1-9]\d?|1\d\d|2[01]\d|22[0-3])(?:\.(?:1?\d{1,2}|2[0-4]\d|25[0-5])){2}(?:\.(?:[1-9]\d?|1\d\d|2[0-4]\d|25[0-4]))|(?:(?:[a-z\u00a1-\uffff0-9]+-?)*[a-z\u00a1-\uffff0-9]+)(?:\.(?:[a-z\u00a1-\uffff0-9]+-?)*[a-z\u00a1-\uffff0-9]+)*(?:\.(?:[a-z\u00a1-\uffff]{2,})))(?::\d{2,5})?(?:\/[^\s]*)?/i.source;

# regex to match urls
@util.url-pattern     = new RegExp url-pattern, 'i'
@util.url-pattern-all = new RegExp url-pattern, 'ig'

@util.replace-urls = (s, fn) ->
  s.replace util.url-pattern-all, fn

# given a url, return its hostname
@util.hostname = (url) ->
  url.match(/^https?:\/\/(.*?)\//)?1

# given a url, find a way to embed it in html
@util.embedded = (url) ->
  h = util.hostname url
  if url.match /\.(jpe?g|png|gif)$/i
    #"""<a href="#{url}" target="_blank"><img src="#{url}" /></a>"""
    [ \a, { href: url, target: \_blank }, [ \img, { src: url } ] ]
  else if h is \www.youtube.com and url.match(/v=(\w+)/)
    [m,v] = url.match(/v=(\w+)/)
    #"""<iframe width="560" height="315" src="//www.youtube.com/embed/#v" frameborder="0" allowfullscreen></iframe>"""
    [ \iframe { width: 560, height: 315, src: "//www.youtube.com/embed/#v", frameborder: 0, allowfullscreen: true } ] # TODO instead of an iframe, do something that delays loading flash
  else
    #"""<a href="#{url}" target="_blank">#{url}</a>"""
    [ \a, { href: url, target: \_blank }, url ]

@util.split = _split = (string, pattern, fn) ->
  m = string.match pattern
  if m
    if m.index is 0
      rest = string.substring(m.0.length)
      if rest.length
        [m.0, ...(_split rest, pattern)]
      else
        [m.0]
    else if m.index > 0
      rest = string.substring(m.index + m.0.length)
      if rest.length
        [string.substring(0, m.index), m.0, ...(_split rest, pattern)]
      else
        [string.substring(0, m.index), m.0]
  else
    [string]

# recurse through the tree and make transformations
@transform = transform = (fn, tree) -->
  [tag, attrs, children] = if is-type \String, tree
    [void, void, tree]
  else if is-type \Array, tree
    if is-type \Object, tree.1
      if tree.length > 2
        [tree.0, tree.1, tree.slice(2)]
      else
        [tree.0, tree.1]
    else
      [tree.0, {}, tree.slice(1)]

  if tag
    if children and children.length

      # this loop was so hard to figure out
      new-children = []
      for c in children
        nc = transform fn, c
        if (is-type \String, c) and (is-type \Array, nc)
          new-children = new-children.concat nc
        else
          new-children.push nc

      [tag, attrs, ...new-children]
    else
      [tag, attrs]
  else
    fn children

@tx = tx = {}

# take a string and return JsonML for embedded links
@tx.auto-embed-link = (s) ->
  r = util.split s, util.url-pattern
  |> map (-> if it.match(util.url-pattern) then [util.embedded(it)] else it)
  |> concat # just flatten one level

@tx.new-line = (s) ->
  r = util.split s, /\n/
  |> map (-> if it.match(/\n/) then [[\br {}]] else it)
  |> concat # just flatten one level

# TODO - #tag support
@tx.hash-tag = (s) ->

# TODO - @tag support
@tx.at-tag = (s) ->

# TODO - bbcode support
@tx.bbcode = (s) ->

# TODO - sanitize html ### use https://code.google.com/p/jquery-clean/
@tx.sanitize = (s) ->

# take text and apply markup rules to it
@render = (text) ->
  esc-text = util.replace-urls text, (url) -> url.replace /_/g, '\\_'
  tree = md.parse esc-text
  |> md.to-HTML-tree
  |> transform tx.auto-embed-link
  |> transform tx.new-line
  |> md.render-json-ML

# create a custom render function
@render-fn = (before-filters, transforms) ->
  (text) ->
    filtered-text = before-filters |> fold ((text, filter) -> filter(text)), text
    tree          = filtered-text  |> md.parse |> md.to-HTML-tree
    tx-tree       = transforms     |> fold ((html-tree, tx) -> transform tx, html-tree), tree
    md.render-json-ML tx-tree

@

# Example:
#
# require! { \pagedown, \./shared/format }
# cv = format.cv pagedown.get-sanitizing-converter!
# cv.make-html "# http://foo.com/img.jpg\n\n* one\n* two\n* three", {}
#
# vim:fdm=indent
