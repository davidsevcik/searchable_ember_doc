(($) ->
  self = null
  $.fn.liveUpdate = (list) ->
    @each ->
      new $.liveUpdate(this, list)


  $.liveUpdate = (e, list) ->
    @field = $(e)
    @list = $("#" + list)
    @init()  if @list.length > 0

  $.liveUpdate:: =
    init: ->
      self = @
      @setupCache()
      @field.parents("form").submit -> false
      @field.keyup (event) ->
        self.filter() if [13, 38, 40].indexOf(event.keyCode) is -1
      @field.keydown (event) ->
        switch event.keyCode
          when 13 #enter
            self.list.find('a.selected').click()
            false
          when 38 #up
            selected = self.list.find('a.selected')
            prev = selected.parent().prevAll(':visible:first')
            if prev.length
              selected.removeClass('selected')
              prev.children('a').addClass('selected')
            false
          when 40 #down
            selected = self.list.find('a.selected')
            next = selected.parent().nextAll(':visible:first')
            if next.length
              selected.removeClass('selected')
              next.children('a').addClass('selected')
            false

      @field.on 'search', -> self.filter()

      @list.find('a').click ->
        self.list.find('a.selected').removeClass('selected')
        $(@).addClass 'selected'

      @filter()

    filter: ->
      if $.trim(@field.val()) is ""
        @list.children("li").show()
        return
      @displayResults @getScores(@field.val().toLowerCase())

    setupCache: ->
      self = this
      @cache = []
      @rows = []
      @list.children("li").each ->
        jqElm = $(@)
        #Shows methods associated with the searched classnames
        className = jqElm.find('.name').text().trim().replace(/^Ember./, '').toLowerCase()
        methodName = jqElm.find('.context').text().trim().replace(/^Ember./, '').toLowerCase()
        self.cache.push  className + ' ' + methodName
        self.rows.push jqElm

      @cache_length = @cache.length

    displayResults: (scores) ->
      @list.children("li").hide()
      @list.find('a.selected').removeClass('selected')
      $.each scores, (i, score) => @rows[score[1]].show()#.find('.score').text(score[0])
      @list.find('li.level-2:visible:first a').addClass 'selected'


    getScores: (term) ->
      scores = []
      i = 0

      while i < @cache_length
        score = @cache[i].score(term)
        scores.push [score, i]  if score > 0
        i++
      scores.sort (a, b) ->
        b[0] - a[0]

) jQuery
