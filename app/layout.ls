# XXX layout-specific client-side

# shortcuts
$w = $ window
$d = $ document

is-ie     = false or \msTransform in document.documentElement.style
is-moz    = false or \MozBoxSizing in document.documentElement.style
is-opera  = !!(window.opera and window.opera.version)
threshold = 10 # snap

$w.v = require './validations'

# main
# ---------
#{{{ Mutant init
window.mutant  = require '../lib/mutant/mutant'
window.mutants = require './mutants'

<- window.mutants[window.mutator].on-load window # fire onLoad of initial mutant
$ '#query' .focus!

$d.on \click 'a.mutant' (e) -> # hijack urls
  href = $ this .attr \href
  return false unless href # guard
  return true if href?.match /#/
  search-params = {}
  History.push-state {search-params}, '', href
  return false

History.Adapter.bind window, \statechange, (e) -> # history manipulaton
  url = History.get-page-url!replace /\/$/, ''
  $.get url, _surf:1, (r) ->
    $d.title = r.locals.title if r.locals?.title # set title
    window.mutant.run window.mutants[r.mutant], locals:r.locals
  return false

#}}}
#{{{ Scrolling behaviors

# indicate to stylus that view scrolled
has-scrolled = ->
  st = $w.scrollTop!
  $ \body .toggle-class 'scrolled' (st > threshold)
set-timeout (->
  $w.on \scroll -> has-scrolled!
  has-scrolled!), 1300 # initially yield

window.awesome-scroll-to = (e, duration, on-complete) ->
  on-complete = -> noop=1 unless on-complete

  e     := $ e
  ms     = duration or 600
  offset = 100

  return unless e.length # guard
  if is-ie or is-opera
    e[0].scroll-into-view!
    on-complete!
  else # animate
    dst-scroll = Math.round(e.position!top) - offset
    cur-scroll = window.scrollY
    if Math.abs(dst-scroll - cur-scroll) > 30
      #<- $ 'html,body' .animate { scroll-top:dst-scroll }, 140
      #<- $ 'html,body' .animate { scroll-top:dst-scroll+threshold }, 110
      <- $ 'html,body' .animate { scroll-top:dst-scroll }, ms
    else
      on-complete!
  e

# attach scroll-to's
$d.on \click '.scroll-to' ->
  awesome-scroll-to $(this).data \scroll-to
  false

# attach scroll-to-top's
$d.on \mousedown '.scroll-to-top' ->
  $ this .attr \title 'Scroll to Top!'
  <- $ 'html,body' .animate { scroll-top:$ \body .offset!top }, 140
  <- $ 'html,body' .animate { scroll-top:$ \body .offset!top+threshold }, 110
  <- $ 'html,body' .animate { scroll-top:$ \body .offset!top }, 75
  false
#}}}

#{{{ Waypoints
$w.resize -> set-timeout (-> $.waypoints \refresh), 800
set-timeout (->
  # sort control
  $ '#sort li' .waypoint {
    context: \ul
    offset : 30
    handler: (direction) ->
      e = $ this # figure active element
      if direction is \up
        e := e.prev!
      e := $ this unless e.length

      $ '#sort li.active' .remove-class \active
      e .add-class \active # set!
  }

  # sticky forum headers
  $ '.forum .header' .waypoint \sticky {
    offset : -100
  }

  # forum switches
  $ '.forum' .waypoint {
    offset  : '33%',
    handler : (direction) ->
      e   = $ this
      eid = e.attr \id

      # handle menu active
      id = if direction is \down then eid else
        $ '#'+eid .prevAll '.forum:first' .attr \id
      return unless id # guard
      $ 'header .menu' .find '.active' .remove-class \active # remove prev
      cur  = $ 'header .menu'
        .find ".#{id.replace /_/ \-}"
        .add-class \active # ...and activate!

      # handle forum headers
      $ '.forum .invisible' .remove-class \invisible
      $ '.forum .stuck'     .remove-class \stuck
      # TODO if direction is \up stick last forum

      # handle forum background
      $ '.bg' .each -> $ this .remove!prependTo $ 'body' # position behind
      clear-timeout window.bg-anim if window.bg-anim
      last = $ '.bg.active'
      unless last.length
        next = $ '#forum'+"_bg_#{cur.data \id}"
        next.add-class \active
      else
        window.bg-anim := set-timeout (->
          next = $ '#forum'+"_bg_#{cur.data \id}"

          last.css \top if direction is \down then -300 else 300 # stage animation
          last.remove-class \active
          next.add-class 'active visible' # ... and switch!
          window.bg-anim = 0
        ), 300
  }), 100
#}}}
#{{{ todo non-layout-specific code (actions and view states) to relocate once mutant++ is pulled in
add-post-dialog = ->
  #xxx: stub code for now, since we have no concept of sub-forums
  # mainly here as a proof-of-concept
  fid = $(this).data \fid

  post-html = '<h1>add post form goes here</h1>'
  html <- $.get '/ajax/add-post', {fid}
  $(html).dialog modal: true
  false # stop event propagation

# assumes immediate parent is form (in case of submit button)
add-post = ->
  form = $ '#add-post-form'
  $.post '/ajax/add-post', form.serialize!, ->
    console.log 'success! post added'
    console.log 'stub: do something fancy to confirm submission'

  false # stop event propagation
# delegated events
$d.on \click '#add-post-submit' add-post
$d.on \click '.onclick-add-post-dialog' add-post-dialog

$d.on \click 'header' (e) ->
  $ \body .remove-class \expanded if e.target.class-name is \header # guard
  $ '#query' .focus!
$d.on \keypress '#query' -> $ \body .add-class \expanded
#}}}
# vim:fdm=marker
