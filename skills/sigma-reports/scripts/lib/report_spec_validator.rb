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
      table text
    ].freeze
    SCHEMA_ONLY_KINDS = %w[
      box-chart button embed funnel-chart gauge-chart input-table plugin
      sankey-chart treemap-chart
    ].freeze
    UNSUPPORTED_KINDS = %w[progress waterfall-chart].freeze
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
      %w[themeName themeOverrides].each do |key|
        errors << "contents.#{key} was removed; use contents.settings.theme" if @contents.key?(key)
      end
      warnings << 'contents.settings is schema-published but not report-proven; preserve readback unchanged and verify carefully' if @contents.key?('settings')
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
      validate_pivot_shelves(element, element_label) if element['kind'] == 'pivot-table'
      validate_series_line_area_style(element, element_label)
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
      Array(COLUMN_ID_POINTER_FIELDS[element['kind']]).each do |field|
        pointer = element[field]
        next unless pointer.is_a?(Hash)

        errors << "element #{element_label} #{field} uses removed id; use columnId" if pointer.key?('id')
      end

      return unless element['kind'] == 'sankey-chart'

      Array(element['stages']).each_with_index do |pointer, index|
        next unless pointer.is_a?(Hash) && pointer.key?('id')

        errors << "element #{element_label} stages[#{index}] uses removed id; use columnId"
      end
    end

    def validate_pivot_shelves(element, element_label)
      %w[rowsBy columnsBy].each do |field|
        Array(element[field]).each_with_index do |pointer, index|
          next unless pointer.is_a?(Hash) && pointer.key?('id')

          errors << "element #{element_label} #{field}[#{index}] uses removed id; use columnId"
        end
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

      root.elements.each do |child|
        if child.name != 'Element'
          errors << "layout #{kind} #{id || '(unnamed)'} may contain only Element leaves, got #{child.name}"
          next
        end
        validate_layout_element(child, root, placements)
      end
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
