require_relative "./highlighter"

module APIDocs
  class << self
    def repo_url
      @repo_url
    end

    def sha
      @sha
    end

    def registered(app, options={})
      app.helpers Helpers

      app.after_configuration do
        all_data = {}
        all_data['modules']     = data.api['modules'].merge data.api_data['modules']
        all_data['classes']     = data.api['classes'].merge data.api_data['classes']
        all_data['files']       = data.api['files'] + data.api_data['files']
        all_data['classitems']  = data.api['classitems'] + data.api_data['classitems']
        ApiClass.data = all_data

        @modules = {}
        data_hash = data.to_h
        data_hash.each do |project_key, docs|
          docs['modules'].each_key {|key| @modules[key] = docs['project'] }
        end

        data_hash.each do |project_key, docs|
          @repo_url = docs['project']['repo_url']
          @sha      = docs['project']['sha']

          # page '/*', directory_index: false, layout: 'layouts/api'

          docs['classes'].each do |name, data|
            page "/classes/#{name}.html", proxy: 'api/class.html', layout: 'layouts/api' do
              @title = name
              @class = ApiClass.find(name)
            end

            if name == options[:default_class]
              page '/default-class.html', proxy: 'api/class.html', layout: 'layouts/api' do
                @title = name
                @class = ApiClass.find(name)
              end
            end
          end

          docs['modules'].each do |name, data|
            page "/modules/#{name}.html", proxy: 'api/module.html', layout: 'layouts/api' do
              @title = name
              @module = data
            end
          end
        end

        # Update data caches
        files.changed("data/*.yml") do
          ApiClass.data = all_data
        end
      end
    end
    alias :included :registered
  end

  class CodeRenderer < Redcarpet::Render::HTML
    include Highlighter::Helpers

    def block_code(code, language)
      _highlight(code, language || 'javascript')
    end
  end

  class ApiClass
    @@cache = {}
    cattr_reader :cache

    @@data = nil
    cattr_reader :data

    def self.data=(value)
      @@cache = {}
      @@data = value
    end

    def self.find(name)
      cache[name] || new(name)
    end

    attr_reader :native

    def initialize(name)
      data = self.class.data['classes'][name]

      if data
        @native = false
        @data = data
      else
        @native = true
        @data = {}
      end
    end

    def to_s
      return self.name
    end

    def extends
      @extends ||= @data['extends'] && self.class.find(@data['extends'])
    end

    def uses
      @uses ||= @data['uses'] ?
                  @data['uses'].map{|u| self.class.find(u) } :
                  []
    end

    def classitems
      unless @classitems
        @classitems = {}

        # Go from root up
        parents = ([extends] + uses.reverse).compact
        parents.each do |parent|
          parent.classitems.each do |type, items|
            items.each do |_, item|
              item = item.clone
              @classitems[item['itemtype']] ||= {}
              existing = @classitems[item['itemtype']][item['name']]
              if existing
                next if existing['class'] == item['class']
                item['overwritten_from'] = existing
              else
                item['extended_from'] = parent
              end
              @classitems[item['itemtype']][item['name']] = item
            end
          end
        end

        self.class.data['classitems'].each do |item|
          next if item['class'] != self.name

          item = item.clone
          @classitems[item['itemtype']] ||= {}
          if existing = @classitems[item['itemtype']][item['name']]
            item['overwritten_from'] = existing
          end
          @classitems[item['itemtype']][item['name']] = item
        end
      end

      @classitems
    end

    def [](attr)
      @data[attr]
    end

    def method_missing(method, *args)
      @data[method]
    end
  end

  module Helpers
    def current?(key)
      request_key = _request_as_key

      category_match = request_key[:category] == key[:category]
      name_match = request_key[:name] == key[:name]

      # logger.info "#{request_key[:category]}, #{request_key[:name]}, #{key[:category]}, #{key[:name]}"

      if key[:name].present?
        category_match and name_match
      else
        category_match
      end
    end

    def _file_to_category(file)
      lookup ||= begin
        obj = {}

        api_modules.map(&:first).each_with_object(obj) do |file, hash|
          hash[file] = :modules
        end

        api_classes.map(&:first).each_with_object(obj) do |file, hash|
          hash[file] = :classes
        end

        api_namespaces.map(&:first).each_with_object(obj) do |file, hash|
          hash[file] = :namespaces
        end
      end

      lookup[file]
    end


    def _request_as_key
      # logger.info request.path
      path = request.path.split('/')
      file = File.basename(path.pop, '.html')

      category = _file_to_category(file)

      {
        name: file,
        category: category
      }
    end

    def _level
      @level ||= 0
      @level += 1
      yield(@level)
      @level -= 1
    end

    def li_for(category, options = {}, &block)
      class_name = options[:class]
      key = {
        category: category,
        name: options[:name]
      }

      _level do |level|
        concat(%Q{
          <li class="level-#{level} #{selected_class(key, class_name)}">
          #{capture(&block)}
          </li>
        })
      end
    end

    def ol_for(category, options = {}, &block)
      class_name = options[:class]

      key = {
        category: category,
        name: options[:name]
      }

      _level do |level|
        concat(%Q{
          <ol class="#{selected_class(key, class_name)}">
          #{capture(&block)}
          </ol>
        })
      end
    end

    def selected_class(key, class_name = nil)
      class_name || 'selected' if current?(key)
    end

    def sha
      data.api.fetch('project')['sha']
    end

    def sha_url
      "#{APIDocs.repo_url}/tree/#{sha}"
    end

    def api_modules
      (data.api['modules'].merge data.api_data['modules']).sort
    end

    def api_classes
      (data.api['classes'].merge data.api_data['classes']).sort
    end

    def api_namespaces
      (data.api['classes'].merge data.api_data['classes']).select{|_,c| c['static'] }.sort
    end

    def api_methods
      (data.api['classitems'] + data.api_data['classitems']).select {|x| x['itemtype'] == 'method' && !/\{/.match(x['name'])}.sort_by {|x| x['name']}
    end

    def api_properties
      (data.api['classitems'] + data.api_data['classitems']).select {|x| x['itemtype'] == 'property' && !/\{/.match(x['name'])}.sort_by {|x| x['name']}
    end

    def api_file_link(item, modules, options = {})
      if modules && item['file'] && (matched = /packages\/([^\/]+)/.match(item['file'])) && (project = modules[matched[1]])
        path = item['file'].sub(/^\.\.\//, '')

        options[:class] ||= 'api-file-link'

        title = path
        link  = "#{project['repo_url']}/tree/#{project['sha']}/#{path}"

        if line = item['line']
          title += ":#{line}"
          link += "#L#{line}"
        end

        title = options.delete(:title) || title

        link_to title, link, options.merge(target: '_blank')
      end
    end

    def api_module(name)
      return name if name.is_a?(Hash)
      data.api['modules'][name]
    end

    def api_class(name)
      return name if name.is_a?(ApiClass)
      name = name['name'] if name.is_a?(Hash)
      ApiClass.find(name)
    end
    alias :api_namespace :api_class

    def api_module_link(name, anchor=nil)
      link = "/modules/#{name}.html"
      link += '#'+anchor if anchor
      link_to name, link
    end

    def api_class_link(name, anchor=nil, &block)
      klass = api_class(name)
      if klass && !klass.native
        link = "/classes/#{name}.html"
        link += '#'+anchor if anchor
        concat link_to(block_given? ? capture(&block) : name, link)
      else
        block_given? ? capture(&block) : name
      end
    end
    alias :api_namespace_link :api_class_link

    def api_method_link(name, clazz, &block)
      klass = api_class(clazz)
      if klass && !klass.native
        link = "/classes/#{clazz}.html"
        link += '#method_' + name
        concat link_to(block_given? ? capture(&block) : name, link)
      else
        block_given? ? capture(&block) : name
      end
    end

    def api_property_link(name, clazz, &block)
      klass = api_class(clazz)
      if klass && !klass.native
        link = "/classes/#{clazz}.html"
        link += '#property_' + name
        concat link_to(block_given? ? capture(&block) : name, link)
      else
        block_given? ? capture(&block) : name
      end
    end

    def api_classes_for_item(item)
      classes = [item['access']]
      classes << 'deprecated' if item['deprecated']
      classes << 'inherited' if item['extended_from']
      classes.compact.join(' ')
    end

    def api_classes_for_class(klass)
      api_classes_for_item(api_class(klass))
    end
    alias :api_classes_for_namespace :api_classes_for_class

    def api_markdown(string)
      Redcarpet::Markdown.new(CodeRenderer,
        :layout_engine => :erb,
        :fenced_code_blocks => true,
        :lax_html_blocks => true).render(string)
    end

    def sanitize_class(string)
      string.gsub(/[^a-z0-9_-]+/i, '_');
    end
  end
end

::Middleman::Extensions.register(:api_docs, APIDocs)
