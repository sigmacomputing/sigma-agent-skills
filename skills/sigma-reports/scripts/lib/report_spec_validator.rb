# frozen_string_literal: true

require 'json'
require 'rexml/document'

module ReportSpec
  class Validator
    MAX_PAGES = 1_000
    MAX_PAGE_DIMENSION = 10_000

    DOCUMENTED_KINDS = %w[
      area-chart bar-chart combo-chart control divider geography-map image
      kpi-chart line-chart pivot-table point-map region-map scatter-chart
      table text waterfall-chart
    ].freeze
    SCHEMA_ONLY_KINDS = %w[
      box-chart button embed funnel-chart gauge-chart input-table plugin
      sankey-chart treemap-chart
    ].freeze
    UNSUPPORTED_KINDS = %w[progress].freeze
    WORKBOOK_ONLY_KINDS = %w[
      chat code container form navigation page-break repeated-container
      single-row-container tabbed-container value-list
    ].freeze
    FORBIDDEN_LAYOUT_ATTRIBUTES = %w[
      gridColumn gridRow gridTemplateColumns gridTemplateRows
    ].freeze
    COLUMN_ID_POINTER_FIELDS = {
      'funnel-chart' => %w[stage series],
      'gauge-chart' => %w[value],
      'geography-map' => %w[geography],
      'point-map' => %w[latitude longitude size],
      'region-map' => %w[region],
      'scatter-chart' => %w[size],
      'treemap-chart' => %w[category]
    }.freeze
    SINGLE_COLUMN_POINTER_FIELDS = %w[
      xAxis value comparisonColumn holeValue geography latitude longitude
      region size category stage series
    ].freeze
    AGGREGATE_FORMULA = /\b(?:sum|count|countdistinct|avg|average|min|max|median|percentile|stddev|variance)\s*\(/i.freeze

    attr_reader :errors, :warnings

    def initialize(payload, mode: :create)
      @payload = payload
      @mode = mode.to_sym
      @errors = []
      @warnings = []
    end

    def validate
      validate_envelope
      return self unless @contents.is_a?(Hash)

      validate_contents
      validate_pages
      validate_panels
      validate_elements
      validate_layout
      self
    end

    def valid?
      errors.empty?
    end

    private

    def validate_envelope
      unless @payload.is_a?(Hash)
        errors << 'root must be a JSON object'
        return
      end

      case @mode
      when :create
        %w[name folderId contents].each do |key|
          errors << "missing required create field: #{key}" unless @payload.key?(key)
        end
      when :update
        errors << 'missing required update field: contents' unless @payload.key?('contents')
        unexpected = @payload.keys - %w[contents documentVersion]
        errors << "update body contains unsupported properties: #{unexpected.join(', ')}" unless unexpected.empty?
        if @payload.key?('documentVersion') &&
           (!@payload['documentVersion'].is_a?(Numeric) || !@payload['documentVersion'].finite?)
          errors << 'update documentVersion must be a finite number'
        end
      else
        errors << "unknown validation mode: #{@mode}"
      end

      @contents = @payload['contents']
      errors << 'contents must be an object' unless @contents.is_a?(Hash)
    end

    def validate_contents
      %w[schemaVersion kind elements pages].each do |key|
        errors << "missing required contents field: #{key}" unless @contents.key?(key)
      end
      errors << 'contents.schemaVersion must be a number' unless @contents['schemaVersion'].is_a?(Numeric)
      errors << 'contents.kind must be report' unless @contents['kind'] == 'report'
      errors << 'contents.elements must be an array' unless @contents['elements'].is_a?(Array)
      errors << 'contents.pages must be an array' unless @contents['pages'].is_a?(Array)
      errors << 'contents.panels must be an array when present' if @contents.key?('panels') && !@contents['panels'].is_a?(Array)
      errors << 'contents.config is required for fixed-page report authoring' unless @contents.key?('config')
      %w[themeName themeOverrides].each do |key|
        errors << "contents.#{key} was removed; use contents.settings.theme" if @contents.key?(key)
      end
      validate_color_overrides

      config = @contents['config']
      if config && !config.is_a?(Hash)
        errors << 'contents.config must be an object when present'
        return
      end
      return unless config

      width = validate_number(config['pageWidth'], 'contents.config.pageWidth', positive: true, max: MAX_PAGE_DIMENSION)
      height = validate_number(config['pageHeight'], 'contents.config.pageHeight', positive: true, max: MAX_PAGE_DIMENSION)
      margin = validate_number(config['margin'], 'contents.config.margin', nonnegative: true)
      errors << 'contents.config.margin must leave positive page width' if width && margin && margin * 2 >= width
      errors << 'contents.config.margin must leave positive page height' if height && margin && margin * 2 >= height
    end

    def validate_pages
      @pages = array(@contents['pages'])
      errors << 'contents.pages must contain at least one page' if @pages.empty?
      errors << "contents.pages exceeds the #{MAX_PAGES}-page limit" if @pages.length > MAX_PAGES

      @page_ids = validate_ids(@pages, 'page')
      @pages.each_with_index do |page, index|
        unless page.is_a?(Hash)
          errors << "contents.pages[#{index}] must be an object"
          next
        end
        errors << "page #{label(page, index)} must have a non-empty name" unless nonempty_string?(page['name'])
        errors << "page #{label(page, index)} must not contain nested elements" if page.key?('elements')
        validate_page_background_image(page, index)
      end
    end

    def validate_page_background_image(page, index)
      return unless page.key?('backgroundImage')

      background = page['backgroundImage']
      page_label = label(page, index)
      unless background.is_a?(Hash)
        errors << "page #{page_label} backgroundImage must be an object"
        return
      end
      errors << "page #{page_label} backgroundImage uses removed flat url; nest it under source" if background.key?('url')
      source = background['source']
      unless source.is_a?(Hash)
        errors << "page #{page_label} backgroundImage must contain a source object"
        return
      end
      if source['kind'] == 'url' && !nonempty_string?(source['url'])
        errors << "page #{page_label} backgroundImage URL source must contain a non-empty url"
      end
    end

    def validate_panels
      @panels = array(@contents['panels'])
      @panel_ids = validate_ids(@panels, 'panel')
      assignments = Hash.new { |hash, key| hash[key] = [] }

      @panels.each_with_index do |panel, index|
        unless panel.is_a?(Hash)
          errors << "contents.panels[#{index}] must be an object"
          next
        end
        panel_label = label(panel, index)
        type = panel['type']
        errors << "panel #{panel_label} type must be header or footer" unless %w[header footer].include?(type)
        errors << "panel #{panel_label} must not contain nested elements" if panel.key?('elements')

        pages = panel['pages']
        if pages && !pages.is_a?(Array)
          errors << "panel #{panel_label} pages must be an array"
        else
          array(pages).each do |page_id|
            errors << "panel #{panel_label} references unknown page: #{page_id}" unless @page_ids.include?(page_id)
            assignments[[page_id, type]] << panel['id'] if %w[header footer].include?(type)
          end
        end

        config = panel['config']
        if config && !config.is_a?(Hash)
          errors << "panel #{panel_label} config must be an object"
        elsif config
          validate_number(config['height'], "panel #{panel_label} config.height", positive: true, max: MAX_PAGE_DIMENSION)
          if config.key?('backgroundColor') && !config['backgroundColor'].is_a?(String)
            errors << "panel #{panel_label} config.backgroundColor must be a string"
          end
        end
      end

      assignments.each do |(page_id, type), panel_ids|
        next unless panel_ids.length > 1

        errors << "page #{page_id} has more than one #{type} panel: #{panel_ids.join(', ')}"
      end
    end

    def validate_elements
      @elements = array(@contents['elements'])
      @element_ids = validate_ids(@elements, 'element')
      @elements_by_id = @elements.each_with_object({}) do |element, out|
        out[element['id']] = element if element.is_a?(Hash) && element['id']
      end
      @columns_by_element = @elements.each_with_object({}) do |element, out|
        next unless element.is_a?(Hash) && element['id']

        out[element['id']] = array(element['columns']).map do |column|
          column['id'] if column.is_a?(Hash)
        end.compact
      end
      @control_ids = @elements.map do |element|
        element['controlId'] if element.is_a?(Hash) && element['kind'] == 'control'
      end.compact

      @elements.each_with_index do |element, index|
        unless element.is_a?(Hash)
          errors << "contents.elements[#{index}] must be an object"
          next
        end
        element_label = label(element, index)
        kind = element['kind']
        unless nonempty_string?(kind)
          errors << "element #{element_label} must have a non-empty kind"
          next
        end

        if UNSUPPORTED_KINDS.include?(kind)
          errors << "element #{element_label} kind #{kind} is unsupported for report authoring"
        elsif WORKBOOK_ONLY_KINDS.include?(kind)
          errors << "element #{element_label} kind #{kind} is workbook-only"
        elsif SCHEMA_ONLY_KINDS.include?(kind)
          warnings << "element #{element_label} kind #{kind} is schema-only; require live verify/readback/PDF evidence"
        elsif !DOCUMENTED_KINDS.include?(kind)
          warnings << "element #{element_label} kind #{kind} is unknown to this support matrix"
        end

        if kind == 'control' && element['controlType'] == 'synced'
          errors << "element #{element_label} uses unsupported synced controlType"
        elsif kind == 'control' && element['controlType'] == 'file-upload'
          warnings << "element #{element_label} uses schema-only file-upload controlType; require live verify/readback/PDF evidence"
        end

        validate_released_element_shapes(element, element_label)
      end
    end

    def validate_released_element_shapes(element, element_label)
      validate_alignment(element, element_label)
      validate_column_id_pointers(element, element_label)
      validate_series_line_area_style(element, element_label)
      validate_local_column_references(element, element_label)
      validate_groupings(element, element_label)
      validate_sql_source(element, element_label)
      validate_formula_qualification(element, element_label)
    end

    def validate_alignment(element, element_label)
      vertical_align = element['verticalAlign']
      if vertical_align && !%w[top center bottom].include?(vertical_align)
        errors << "element #{element_label} verticalAlign must be top, center, or bottom"
      end

      if element['kind'] == 'divider' && element['align']
        allowed = element['direction'] == 'vertical' ? %w[left center right] : %w[top center bottom]
        unless allowed.include?(element['align'])
          errors << "element #{element_label} align must be #{allowed.join(', ')} for #{element['direction'] || 'horizontal'} divider"
        end
      end

      return unless element['kind'] == 'kpi-chart' && element['layout'].is_a?(Hash)

      anchor = element['layout']['anchor']
      if anchor && !%w[left center right].include?(anchor)
        errors << "element #{element_label} layout.anchor must be left, center, or right"
      end
      vertical_anchor = element['layout']['verticalAnchor']
      if vertical_anchor && !%w[top center bottom].include?(vertical_anchor)
        errors << "element #{element_label} layout.verticalAnchor must be top, center, or bottom"
      end
    end

    def validate_column_id_pointers(element, element_label)
      walk = lambda do |value, path|
        case value
        when Hash
          value.each do |key, child|
            if key.to_s.downcase == 'columnid' && key != 'columnId'
              errors << "element #{element_label} #{(path + [key]).join('.')} must use camelCase columnId"
            end
            walk.call(child, path + [key])
          end
        when Array
          value.each_with_index { |child, index| walk.call(child, path + [index]) }
        end
      end
      walk.call(element, [])

      SINGLE_COLUMN_POINTER_FIELDS.each do |field|
        pointer = element[field]
        next unless pointer.is_a?(Hash) && pointer.key?('id') && !pointer.key?('columnId')

        errors << "element #{element_label} #{field} uses removed id; use columnId"
      end
      %w[rowsBy columnsBy].each do |field|
        Array(element[field]).each_with_index do |pointer, index|
          next unless pointer.is_a?(Hash) && pointer.key?('id') && !pointer.key?('columnId')

          errors << "element #{element_label} #{field}[#{index}] uses removed id; use columnId"
        end
      end
      Array(element['stages']).each_with_index do |pointer, index|
        next unless pointer.is_a?(Hash) && pointer.key?('id') && !pointer.key?('columnId')

        errors << "element #{element_label} stages[#{index}] uses removed id; use columnId"
      end
      color = element['color']
      if color.is_a?(Hash) && color.key?('id') && !color.key?('columnId')
        errors << "element #{element_label} color uses removed id; use columnId"
      end
      start_value = element.dig('startPoint', 'value')
      if start_value.is_a?(Hash) && start_value['type'] == 'column' &&
         start_value.key?('id') && !start_value.key?('columnId')
        errors << "element #{element_label} startPoint.value uses removed id; use columnId"
      end
    end

    def validate_series_line_area_style(element, element_label)
      return unless element.key?('seriesLineAreaStyle')

      styles = element['seriesLineAreaStyle']
      unless styles.is_a?(Array)
        errors << "element #{element_label} seriesLineAreaStyle must be a list of {columnId, style} objects"
        return
      end
      styles.each_with_index do |entry, index|
        next unless entry.is_a?(Hash)

        errors << "element #{element_label} seriesLineAreaStyle[#{index}] uses removed id; use columnId" if entry.key?('id')
      end
    end

    def validate_local_column_references(element, element_label)
      local_ids = @columns_by_element[element['id']] || []
      source = element['source']
      if source.is_a?(Hash) && source['kind'] == 'table' &&
         source['elementId'] && !@elements_by_id.key?(source['elementId'])
        errors << "element #{element_label} source references unknown element #{source['elementId'].inspect}"
      end
      check = lambda do |pointer, path, valid_ids = local_ids|
        if pointer.is_a?(Hash)
          return if pointer.key?('id') && !pointer.key?('columnId')

          pointer = pointer['columnId']
        end
        return if pointer.nil?
        return if valid_ids.include?(pointer)

        errors << "element #{element_label} #{path} references undeclared column #{pointer.inspect}"
      end

      SINGLE_COLUMN_POINTER_FIELDS.each do |field|
        pointer = element[field]
        check.call(pointer, field) if pointer.is_a?(Hash)
      end
      %w[yAxis yAxis2].each do |axis|
        Array(element.dig(axis, 'columnIds')).each_with_index do |pointer, index|
          check.call(pointer, "#{axis}.columnIds[#{index}]")
        end
      end
      %w[rowsBy columnsBy].each do |shelf|
        Array(element[shelf]).each_with_index do |pointer, index|
          check.call(pointer, "#{shelf}[#{index}]")
        end
        Array(element.dig('trellis', shelf)).each_with_index do |pointer, index|
          check.call(pointer, "trellis.#{shelf}[#{index}]")
        end
      end
      Array(element['seriesLineAreaStyle']).each_with_index do |pointer, index|
        check.call(pointer, "seriesLineAreaStyle[#{index}]")
      end
      if element['kind'] == 'pivot-table'
        Array(element['values']).each_with_index do |pointer, index|
          check.call(pointer, "values[#{index}]")
        end
      end
      Array(element['order']).each_with_index do |pointer, index|
        check.call(pointer, "order[#{index}]")
      end
      Array(element['sort']).each_with_index do |sort, index|
        next unless sort.is_a?(Hash) && sort['columnId']

        check.call(sort['columnId'], "sort[#{index}].columnId")
      end
      color = element['color']
      if color.is_a?(Hash)
        check.call(color, 'color') if color['columnId']
        check.call(color['column'], 'color.column') if color['column']
      end
      start_value = element.dig('startPoint', 'value')
      if start_value.is_a?(Hash) && start_value['type'] == 'column'
        check.call(start_value, 'startPoint.value')
      end

      Array(element['filters']).each_with_index do |filter, index|
        next unless filter.is_a?(Hash) && filter['columnId']

        target_id = filter.dig('source', 'elementId')
        if target_id
          unless @elements_by_id.key?(target_id)
            errors << "element #{element_label} filters[#{index}] targets unknown element #{target_id.inspect}"
            next
          end
          check.call(filter['columnId'], "filters[#{index}].columnId", @columns_by_element[target_id] || [])
        else
          check.call(filter['columnId'], "filters[#{index}].columnId")
        end
      end

      return unless element['kind'] == 'control'

      source = element['source']
      return unless source.is_a?(Hash) && source['columnId']

      target_id = source.dig('source', 'elementId')
      unless @elements_by_id.key?(target_id)
        errors << "element #{element_label} source targets unknown element #{target_id.inspect}"
        return
      end
      check.call(source['columnId'], 'source.columnId', @columns_by_element[target_id] || [])
    end

    def validate_groupings(element, element_label)
      return unless element['kind'] == 'table'

      columns = Array(element['columns']).select { |column| column.is_a?(Hash) }
      columns_by_id = columns.each_with_object({}) { |column, out| out[column['id']] = column if column['id'] }
      groupings = Array(element['groupings'])
      aggregate_columns = columns.select { |column| column['formula'].to_s.match?(AGGREGATE_FORMULA) }
      if groupings.empty?
        unless aggregate_columns.empty?
          ids = aggregate_columns.map { |column| column['id'] || column['name'] }.compact
          errors << "element #{element_label} has aggregate columns but no groupings: #{ids.join(', ')}"
        end
        return
      end

      referenced = []
      groupings.each_with_index do |grouping, index|
        unless grouping.is_a?(Hash)
          errors << "element #{element_label} groupings[#{index}] must be an object"
          next
        end
        group_by = Array(grouping['groupBy'])
        calculations = Array(grouping['calculations'])
        referenced.concat(group_by, calculations)
        (group_by + calculations).each do |column_id|
          next if columns_by_id.key?(column_id)

          errors << "element #{element_label} groupings[#{index}] references undeclared column #{column_id.inspect}"
        end
        calculations.each do |column_id|
          column = columns_by_id[column_id]
          next unless column
          next if column['formula'].to_s.match?(AGGREGATE_FORMULA)

          errors << "element #{element_label} groupings[#{index}].calculations references non-aggregate column #{column_id.inspect}"
        end
        Array(grouping['sort']).each_with_index do |sort, sort_index|
          next unless sort.is_a?(Hash) && sort['columnId']
          next if columns_by_id.key?(sort['columnId'])

          errors << "element #{element_label} groupings[#{index}].sort[#{sort_index}] references undeclared column #{sort['columnId'].inspect}"
        end
      end
      visible_extras = columns.reject { |column| column['hidden'] || referenced.include?(column['id']) }
      unless visible_extras.empty?
        ids = visible_extras.map { |column| column['id'] || column['name'] }.compact
        warnings << "element #{element_label} leaves visible detail columns outside groupBy/calculations: #{ids.join(', ')}"
      end
    end

    def validate_sql_source(element, element_label)
      source = element['source']
      return unless source.is_a?(Hash) && source['kind'] == 'sql'

      errors << "element #{element_label} SQL source requires connectionId" unless nonempty_string?(source['connectionId'])
      errors << "element #{element_label} SQL source requires statement" unless nonempty_string?(source['statement'])
      Array(element['columns']).each_with_index do |column, index|
        next unless column.is_a?(Hash)

        errors << "element #{element_label} SQL column #{index} requires name" unless nonempty_string?(column['name'])
        formula = column['formula'].to_s
        unless formula.include?('[Custom SQL/')
          errors << "element #{element_label} SQL column #{column['id'] || index} must reference [Custom SQL/<alias>]"
        end
      end
    end

    def validate_formula_qualification(element, element_label)
      source = element['source']
      return unless source.is_a?(Hash)
      return if %w[warehouse-table sql].include?(source['kind'])

      columns = Array(element['columns']).select { |column| column.is_a?(Hash) }
      sibling_names = columns.map { |column| column['name'] }.compact
      columns.each do |column|
        formula = column['formula'].to_s
        formula_without_strings = formula.gsub(/"[^"]*"|'[^']*'/, '')
        bare_references = formula_without_strings.scan(/\[([^\/\]]+)\]/).flatten
        unresolved = bare_references.reject do |reference|
          sibling_names.include?(reference) || @control_ids.include?(reference)
        end.uniq
        next if unresolved.empty?

        errors << "element #{element_label} column #{column['id'] || column['name']} has unresolved bare references: #{unresolved.join(', ')}"
      end
    end

    def validate_color_overrides
      settings = @contents['settings']
      return unless settings.is_a?(Hash)

      theme = settings['theme']
      return unless theme.is_a?(Hash)

      theme_overrides = theme['overrides']
      return unless theme_overrides.is_a?(Hash)

      overrides = theme_overrides['colorOverrides']
      return if overrides.nil?

      unless overrides.is_a?(Array)
        errors << 'contents.settings.theme.overrides.colorOverrides must be a list of {name, color} objects'
        return
      end
      overrides.each_with_index do |entry, index|
        unless entry.is_a?(Hash) && nonempty_string?(entry['name']) && nonempty_string?(entry['color'])
          errors << "contents.settings.theme.overrides.colorOverrides[#{index}] must contain non-empty name and color"
        end
      end
    end

    def validate_layout
      layout = @contents['layout']
      if @elements.any? && !nonempty_string?(layout)
        errors << 'contents.layout is required when contents.elements is non-empty'
        return
      end
      return unless nonempty_string?(layout)

      if layout.match?(/<!DOCTYPE|<!ENTITY/i)
        errors << 'contents.layout must not contain a DOCTYPE or ENTITY declaration'
        return
      end

      fragment = layout.sub(/\A\s*<\?xml[^?]*\?>\s*/m, '')
      xml = REXML::Document.new("<ReportLayout>#{fragment}</ReportLayout>")
      placements = Hash.new(0)
      page_roots = []
      panel_roots = []

      xml.root.elements.each do |root|
        case root.name
        when 'Page'
          page_roots << root.attributes['id']
          validate_region_root(root, 'Page', @page_ids, placements)
        when 'Panel'
          panel_roots << root.attributes['id']
          validate_region_root(root, 'Panel', @panel_ids, placements)
          validate_panel_root(root)
        else
          errors << "layout top-level node must be Page or Panel, got #{root.name}"
        end
      end

      validate_root_coverage(page_roots, @page_ids, 'page')
      validate_root_coverage(panel_roots, @panel_ids, 'panel')
      placements.each do |element_id, count|
        errors << "layout references undeclared elementId: #{element_id}" unless @element_ids.include?(element_id)
        errors << "element is placed more than once in layout: #{element_id}" if count > 1
      end
      (@element_ids - placements.keys).each { |id| errors << "element is not placed in layout: #{id}" }
    rescue REXML::ParseException => e
      errors << "contents.layout is invalid XML: #{e.message.lines.first.strip}"
    end

    def validate_region_root(root, kind, declared_ids, placements)
      id = root.attributes['id']
      errors << "layout #{kind} is missing id" unless nonempty_string?(id)
      errors << "layout #{kind} references undeclared #{kind.downcase} id: #{id}" if nonempty_string?(id) && !declared_ids.include?(id)
      reject_grid_attributes(root, "layout #{kind} #{id || '(unnamed)'}")

      rectangles = []
      root.elements.each do |child|
        if child.name != 'Element'
          errors << "layout #{kind} #{id || '(unnamed)'} may contain only Element leaves, got #{child.name}"
          next
        end
        rectangle = validate_layout_element(child, root, placements)
        rectangles << rectangle if rectangle
      end
      validate_overlaps(rectangles, "#{kind} #{id || '(unnamed)'}")
    end

    def validate_layout_element(node, root, placements)
      element_id = node.attributes['elementId']
      unless nonempty_string?(element_id)
        errors << "layout Element under #{root.name} #{root.attributes['id']} is missing elementId"
        return
      end
      placements[element_id] += 1
      reject_grid_attributes(node, "layout Element #{element_id}")
      errors << "layout Element #{element_id} must not contain child nodes" if node.has_elements?

      x = validate_xml_number(node, 'x', element_id, nonnegative: true)
      y = validate_xml_number(node, 'y', element_id, nonnegative: true)
      width = validate_xml_number(node, 'width', element_id, positive: true)
      height = validate_xml_number(node, 'height', element_id, positive: true)
      return unless x && y && width && height

      page_width = number(@contents.dig('config', 'pageWidth'))
      region_height = if root.name == 'Panel'
                        panel = @panels.find { |entry| entry.is_a?(Hash) && entry['id'] == root.attributes['id'] }
                        number(panel&.dig('config', 'height'))
                      else
                        number(@contents.dig('config', 'pageHeight'))
                      end
      errors << "layout Element #{element_id} exceeds page width" if page_width && x + width > page_width
      errors << "layout Element #{element_id} exceeds #{root.name.downcase} height" if region_height && y + height > region_height
      {id: element_id, x: x, y: y, width: width, height: height}
    end

    def validate_overlaps(rectangles, region_label)
      rectangles.combination(2).each do |left, right|
        overlaps = left[:x] < right[:x] + right[:width] &&
                   right[:x] < left[:x] + left[:width] &&
                   left[:y] < right[:y] + right[:height] &&
                   right[:y] < left[:y] + left[:height]
        next unless overlaps

        errors << "layout #{region_label} elements #{left[:id]} and #{right[:id]} overlap"
      end
    end

    def validate_panel_root(root)
      panel = @panels.find { |entry| entry.is_a?(Hash) && entry['id'] == root.attributes['id'] }
      type = root.attributes['type']
      errors << "layout Panel #{root.attributes['id']} type must be header or footer" unless %w[header footer].include?(type)
      return unless panel && type

      errors << "layout Panel #{root.attributes['id']} type #{type} does not match metadata type #{panel['type']}" if panel['type'] != type
    end

    def validate_root_coverage(actual, declared, kind)
      actual.compact.group_by(&:itself).each do |id, copies|
        errors << "#{kind} is declared more than once in layout: #{id}" if copies.length > 1
      end
      (declared - actual.compact).each { |id| errors << "#{kind} is missing from layout: #{id}" }
    end

    def reject_grid_attributes(node, label)
      FORBIDDEN_LAYOUT_ATTRIBUTES.each do |attribute|
        errors << "#{label} uses forbidden workbook attribute #{attribute}" if node.attributes[attribute]
      end
    end

    def validate_xml_number(node, attribute, element_id, positive: false, nonnegative: false)
      raw = node.attributes[attribute]
      unless raw
        errors << "layout Element #{element_id} is missing #{attribute}"
        return
      end
      value = number(raw)
      unless value
        errors << "layout Element #{element_id} #{attribute} must be a finite number"
        return
      end
      errors << "layout Element #{element_id} #{attribute} must be positive" if positive && value <= 0
      errors << "layout Element #{element_id} #{attribute} must be non-negative" if nonnegative && value.negative?
      value
    end

    def validate_number(value, label, positive: false, nonnegative: false, max: nil)
      return unless value

      parsed = number(value)
      unless parsed
        errors << "#{label} must be a finite number"
        return
      end
      errors << "#{label} must be positive" if positive && parsed <= 0
      errors << "#{label} must be non-negative" if nonnegative && parsed.negative?
      errors << "#{label} must not exceed #{max}" if max && parsed > max
      parsed
    end

    def validate_ids(entries, kind)
      ids = []
      entries.each_with_index do |entry, index|
        next unless entry.is_a?(Hash)

        id = entry['id']
        if nonempty_string?(id)
          ids << id
        else
          errors << "#{kind} at index #{index} must have a non-empty id"
        end
      end
      ids.group_by(&:itself).each do |id, copies|
        errors << "duplicate #{kind} id: #{id}" if copies.length > 1
      end
      ids.uniq
    end

    def number(value)
      parsed = Float(value)
      parsed if parsed.finite?
    rescue ArgumentError, TypeError
      nil
    end

    def array(value)
      value.is_a?(Array) ? value : []
    end

    def nonempty_string?(value)
      value.is_a?(String) && !value.strip.empty?
    end

    def label(entry, index)
      entry['id'] || "at index #{index}"
    end
  end
end
