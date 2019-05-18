# The legacy module is what is left of the single javascript
# file that once was Smallest Federated Wiki. Execution still
# starts here and many event dispatchers are set up before
# the user takes control.

pageHandler = require './pageHandler'
state = require './state'
active = require './active'
refresh = require './refresh'
lineup = require './lineup'
drop = require './drop'
dialog = require './dialog'
link = require './link'
target = require './target'
license = require './license'

asSlug = require('./page').asSlug
newPage = require('./page').newPage

# performed in datHandler, as factories.json does not exist in dat variant.  
#wiki.origin.get 'system/factories.json', (error, data) ->
#  window.catalog = data

$ ->
  dialog.emit()

# FUNCTIONS used by plugins and elsewhere


  LEFTARROW = 37
  RIGHTARROW = 39

  $(document).keydown (event) ->
    direction = switch event.which
      when LEFTARROW then -1
      when RIGHTARROW then +1
    if direction && not $(event.target).is(":input")
      pages = $('.page')
      newIndex = pages.index($('.active')) + direction
      if 0 <= newIndex < pages.length
        active.set(pages.eq(newIndex))

# HANDLERS for jQuery events

  #STATE -- reconfigure state based on url
  $(window).on 'popstate', state.show

  $(document)
    .ajaxError (event, request, settings) ->
      return if request.status == 0 or request.status == 404
      console.log 'ajax error', event, request, settings
      # $('.main').prepend """
      #   <li class='error'>
      #     Error on #{settings.url}: #{request.responseText}
      #   </li>
      # """

  commas = (number) ->
    "#{number}".replace /(\d)(?=(\d\d\d)+(?!\d))/g, "$1,"

  readFile = (file) ->
    if file?.type == 'application/json'
      reader = new FileReader()
      reader.onload = (e) ->
        result = e.target.result
        pages = JSON.parse result
        resultPage = newPage()
        resultPage.setTitle "Import from #{file.name}"
        resultPage.addParagraph """
          Import of #{Object.keys(pages).length} pages
          (#{commas file.size} bytes)
          from an export file dated #{file.lastModifiedDate}.
        """
        resultPage.addItem {type: 'importer', pages: pages}
        link.showResult resultPage
      reader.readAsText(file)

  deletePage = (pageObject, $page) ->
    console.log 'fork to delete'
    pageHandler.delete pageObject, $page, (err) ->
      console.log "legacy - deletePage ", err
      return if err?
      console.log 'server delete successful'
      if pageObject.isRecycler()
        # make recycler page into a ghost
        $page.addClass('ghost')
      else
        futurePage = refresh.newFuturePage(pageObject.getTitle(), pageObject.getCreate())
        pageObject.become futurePage
        $page.attr 'id', futurePage.getSlug()
        refresh.rebuildPage pageObject, $page
        $page.addClass('ghost')

  getTemplate = (slug, done) ->
    return done(null) unless slug
    console.log 'getTemplate', slug
    pageHandler.get
      whenGotten: (pageObject,siteFound) -> done(pageObject)
      whenNotGotten: -> done(null)
      pageInformation: {slug: slug}

  finishClick = (e, name) ->
    e.preventDefault()
    page = $(e.target).parents('.page') unless e.shiftKey
    link.doInternalLink name, page, $(e.target).data('site')
    return false

  $('.main')
    .sortable({handle: '.page-handle', cursor: 'grabbing'})
      .on 'sortstart', (evt, ui) ->
        return if not ui.item.hasClass('page')
        noScroll = true
        active.set ui.item, noScroll
      .on 'sort', (evt, ui) ->
        return if not ui.item.hasClass('page')
        $page = ui.item
        # Only mark for removal if there's more than one page (+placeholder) left
        if evt.pageY < 0 and $(".page").length > 2
          $page.addClass('pending-remove')
        else
          $page.removeClass('pending-remove')

      .on 'sortstop', (evt, ui) ->
        return if not ui.item.hasClass('page')
        $pages = $('.page')
        index = $pages.index($('.active'))
        if ui.item.hasClass('pending-remove')
          return if $pages.length == 1
          index = index - 1 if $pages.length - 1 == index
          lineup.removeKey(ui.item.data('key'))
          ui.item.remove()
          active.set($('.page')[index])
        else
          lineup.changePageIndex(ui.item.data('key'), index)
          active.set $('.active')
        state.setUrl()
        state.debugStates()

    .delegate '.show-page-license', 'click', (e) ->
      e.preventDefault()
      $page = $(this).parents('.page')
      title = $page.find('h1').text().trim()
      dialog.open "License for #{title}", license.info($page)

    .delegate '.show-page-source', 'click', (e) ->
      e.preventDefault()
      $page = $(this).parents('.page')
      page = lineup.atKey($page.data('key')).getRawPage()
      dialog.open "JSON for #{page.title}",  $('<pre/>').text(JSON.stringify(page, null, 2))

    .delegate '.page', 'click', (e) ->
      active.set this unless $(e.target).is("a")

    .delegate '.internal', 'click', (e) ->
      name = $(e.target).data 'pageName'
      # ensure that name is a string (using string interpolation)
      name = "#{name}"
      pageHandler.context = $(e.target).attr('title').split(' => ')
      finishClick e, name

    .delegate 'img.remote', 'click', (e) ->
      # expand to handle click on temporary flag
      if $(e.target).attr('src').startsWith('data:image/png')
        e.preventDefault()
        site = $(e.target).data('site')
        wiki.site(site).refresh () ->
          # empty function...
      else
        name = $(e.target).data('slug')
        pageHandler.context = [$(e.target).data('site')]
        finishClick e, name

    .delegate '.revision', 'dblclick', (e) ->
      e.preventDefault()
      $page = $(this).parents('.page')
      page = lineup.atKey($page.data('key')).getRawPage()
      rev = page.journal.length-1
      action = page.journal[rev]
      json = JSON.stringify(action, null, 2)
      dialog.open "Revision #{rev}, #{action.type} action", $('<pre/>').text(json)

    .delegate '.action', 'click', (e) ->
      e.preventDefault()
      $action = $(e.target)
      if $action.is('.fork') and (name = $action.data('slug'))?
        pageHandler.context = [$action.data('site')]
        finishClick e, (name.split '_')[0]
      else
        $page = $(this).parents('.page')
        key = $page.data('key')
        slug = lineup.atKey(key).getSlug()
        rev = $(this).parent().children().not('.separator').index($action)
        return if rev < 0
        $page.nextAll().remove() unless e.shiftKey
        lineup.removeAllAfterKey(key) unless e.shiftKey
        link.createPage("#{slug}_rev#{rev}", $page.data('site'))
          .appendTo($('.main'))
          .each refresh.cycle
        active.set($('.page').last())

    .delegate '.fork-page', 'click', (e) ->
      $page = $(e.target).parents('.page')
      return if $page.find('.future').length
      pageObject = lineup.atKey $page.data('key')
      if $page.attr('id').match /_rev0$/
        deletePage pageObject, $page
      else
        action = {type: 'fork'}
        if $page.hasClass('local')
          return if pageHandler.useLocalStorage()
          $page.removeClass('local')
        else if pageObject.isRecycler()
          $page.removeClass('recycler')
        else if pageObject.isRemote()
          action.site = pageObject.getRemoteSite()
        if $page.data('rev')?
          $page.find('.revision').remove()
        $page.removeClass 'ghost'
        pageHandler.put $page, action

    .delegate 'button.create', 'click', (e) ->
      getTemplate $(e.target).data('slug'), (template) ->
        $page = $(e.target).parents('.page:first')
        $page.removeClass 'ghost'
        pageObject = lineup.atKey $page.data('key')
        pageObject.become(template)
        page = pageObject.getRawPage()
        refresh.rebuildPage pageObject, $page.empty()
        pageHandler.put $page, {type: 'create', id: page.id, item: {title:page.title, story:page.story}}

    .delegate '.score', 'mouseenter mouseleave', (e) ->
      console.log "in .score..."
      $('.main').trigger 'thumb', $(e.target).data('thumb')

    .delegate 'a.search', 'click', (e) ->
      $page = $(e.target).parents('.page')
      key = $page.data('key')
      pageObject = lineup.atKey key
      resultPage = newPage()
      resultPage.setTitle "Search from '#{pageObject.getTitle()}'"
      resultPage.addParagraph """
          Search for pages related to '#{pageObject.getTitle()}'.
          Each search on this page will find pages related in a different way.
          Choose the search of interest. Be patient.
      """
      resultPage.addParagraph "Find pages with links to this title."
      resultPage.addItem
        type: 'search'
        text: "SEARCH LINKS #{pageObject.getSlug()}"
      resultPage.addParagraph "Find pages with titles similar to this title."
      resultPage.addItem
        type: 'search'
        text: "SEARCH SLUGS #{pageObject.getSlug()}"
      resultPage.addParagraph "Find pages neighboring  this site."
      resultPage.addItem
        type: 'search'
        text: "SEARCH SITES #{pageObject.getRemoteSite(location.host)}"
      resultPage.addParagraph "Find pages sharing any of these items."
      resultPage.addItem
        type: 'search'
        text: "SEARCH ANY ITEMS #{(item.id for item in pageObject.getRawPage().story).join ' '}"
      $page.nextAll().remove() unless e.shiftKey
      lineup.removeAllAfterKey(key) unless e.shiftKey
      link.showResult resultPage

    .bind 'dragenter', (evt) -> evt.preventDefault()
    .bind 'dragover', (evt) -> evt.preventDefault()
    .bind "drop", drop.dispatch
      page: (item) -> link.doInternalLink item.slug, null, item.site
      file: (file) -> readFile file

  $(".provider input").click ->
    $("footer input:first").val $(this).attr('data-provider')
    $("footer form").submit()

  $('body').on 'new-neighbor-done', (e, neighbor) ->
    $('.page').each (index, element) ->
      refresh.emitTwins $(element)

  getPluginReference = (title) ->
    return new Promise((resolve, reject) ->
      slug = asSlug(title)
      wiki.origin.get "#{slug}.json", (error, data) ->
        resolve {
          title,
          slug,
          type: "reference",
          text: (if error then error.msg else data?.story[0].text) or ""
        }
      )

  $("<span>&nbsp; ☰ </span>")
    .css({"cursor":"pointer"})
    .appendTo('footer')
    .click ->
      resultPage = newPage()
      resultPage.setTitle "Selected Plugin Pages"
      resultPage.addParagraph """
        Installed plugins offer these utility pages:
      """
      return unless window.catalog

      titles = []
      for info in window.catalog
        if info.pages
          for title in info.pages
            titles.push title

      Promise.all(titles.map(getPluginReference)).then (items) ->
        items.forEach (item) ->
          resultPage.addItem item
        link.showResult resultPage

  # $('.editEnable').is(':visible')
  $("<span>&nbsp; wiki <span class=editEnable>✔︎</span> &nbsp; </span>")
    .css({"cursor":"pointer"})
    .appendTo('footer')
    .click ->
      $('.editEnable').toggle()
      $('.page').each ->
        $page = $(this)
        pageObject = lineup.atKey $page.data('key')
        refresh.rebuildPage pageObject, $page.empty()
  $('.editEnable').toggle() unless isAuthenticated

  target.bind()

  $ ->
    state.first()
    $('.page').each refresh.cycle
    active.set($('.page').last())
