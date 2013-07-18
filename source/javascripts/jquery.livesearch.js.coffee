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
      self = this
      @setupCache()
      @field.parents("form").submit ->
        false

      @field.keyup ->
        self.filter()

      self.filter()

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
        self.cache.push jqElm.text().trim().replace(/^Ember./, '').toLowerCase()
        self.rows.push jqElm

      @cache_length = @cache.length

    displayResults: (scores) ->
      @list.children("li").hide()
      $.each scores, (i, score) =>
        @rows[score[1]].show()#.find('.score').text(score[0])


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
