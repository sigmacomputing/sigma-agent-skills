# frozen_string_literal: true

require 'base64'
require 'cgi'
require 'json'

module ReportSpec
  # Small, dependency-free composition layer for Sigma's fixed-page report
  # representation. It owns geometry and layout assembly; callers still author
  # normal Sigma element hashes.
  class Builder
    PAPER_SIZES = {
      'letter-portrait' => [816, 1056],
      'letter-landscape' => [1056, 816],
      'legal-portrait' => [816, 1344],
      'legal-landscape' => [1344, 816],
      'tabloid-landscape' => [1632, 1056],
      'a4-portrait' => [794, 1123],
      'a4-landscape' => [1123, 794]
    }.freeze

    DEFAULT_BRAND = {
      'primary' => '#1A70F1',
      'deep' => '#0A2E70',
      'ink' => '#111114',
      'muted' => '#5F5F66',
      'line' => '#E5E5E9',
      'surface' => '#F7F7F8',
      'paper' => '#FFFFFF',
      'success' => '#1F9D55',
      'warning' => '#C77A0A',
      'danger' => '#D14343',
      'categorical' => %w[#1A70F1 #1F9D55 #F5A524 #B45BFF #FF6B5A #00BFA5 #5468FF #C2C2C9]
    }.freeze

    attr_reader :name, :folder_id, :contents, :brand

    def initialize(name:, folder_id:, paper: 'letter-portrait', margin: 30, brand: {})
      size = PAPER_SIZES.fetch(paper) do
        raise ArgumentError, "unknown paper #{paper.inspect}; choose #{PAPER_SIZES.keys.join(', ')}"
      end
      @name = required_string(name, 'name')
      @folder_id = required_string(folder_id, 'folder_id')
      @brand = DEFAULT_BRAND.merge(stringify_keys(brand))
      @paper = paper
      @elements = []
      @element_ids = {}
      @pages = []
      @panels = []
      @regions = {}
      @contents = {
        'schemaVersion' => 1,
        'kind' => 'report',
        'config' => {
          'pageWidth' => size[0],
          'pageHeight' => size[1],
          'margin' => margin
        },
        'elements' => @elements,
        'pages' => @pages,
        'panels' => @panels,
        'settings' => {
          'theme' => {
            'overrides' => {
              'colors' => {
                'text' => @brand['ink'],
                'highlight' => @brand['primary'],
                'success' => @brand['success'],
                'warning' => @brand['warning'],
                'danger' => @brand['danger'],
                'darkMode' => 'hidden'
              },
              'colorOverrides' => [],
              'categoricalScheme' => @brand['categorical'],
              'space' => {'unit' => 'small', 'showElementPadding' => 'shown'}
            }
          }
        }
      }
    end

    def page_width
      contents.dig('config', 'pageWidth')
    end

    def page_height
      contents.dig('config', 'pageHeight')
    end

    def margin
      contents.dig('config', 'margin')
    end

    def content_width
      page_width - (2 * margin)
    end

    def add_page(id:, name:, hidden: false)
      id = register_region(id, 'Page')
      page = {'id' => id, 'name' => required_string(name, 'page name')}
      page['visibility'] = 'hidden' if hidden
      @pages << page
      id
    end

    def add_panel(id:, type:, height:, pages:, title: nil, background: '')
      raise ArgumentError, 'panel type must be header or footer' unless %w[header footer].include?(type)

      id = register_region(id, 'Panel', type)
      @panels << {
        'id' => id,
        'type' => type,
        'title' => title || "#{type.capitalize} panel",
        'config' => {'height' => positive_number(height, 'panel height'), 'backgroundColor' => background},
        'pages' => Array(pages)
      }
      id
    end

    def place(element, region:, x:, y:, width:, height:)
      region_info = @regions[region]
      raise ArgumentError, "unknown region #{region.inspect}" unless region_info
      raise ArgumentError, 'element must be an object' unless element.is_a?(Hash)

      id = required_string(element['id'], 'element id')
      raise ArgumentError, "duplicate element id #{id.inspect}" if @element_ids[id]

      rect = {
        'elementId' => id,
        'x' => nonnegative_number(x, 'x'),
        'y' => nonnegative_number(y, 'y'),
        'width' => positive_number(width, 'width'),
        'height' => positive_number(height, 'height')
      }
      @element_ids[id] = true
      @elements << element
      region_info.fetch('placements') << rect
      id
    end

    def text(id:, body:, color: nil, font_size: nil, align: nil, vertical_align: nil)
      content = body.to_s
      styles = []
      styles << "color: #{color}" if color
      styles << "font-size: #{font_size}px" if font_size
      content = %(<span style="#{styles.join('; ')}">#{content}</span>) unless styles.empty?
      content = %(<p style="text-align: #{align}">#{content}</p>) if align
      element = {
        'id' => required_string(id, 'text id'),
        'kind' => 'text',
        'body' => content,
        'style' => {'backgroundColor' => 'transparent', 'padding' => 'none'}
      }
      element['verticalAlign'] = vertical_align if vertical_align
      element
    end

    def svg_image(id:, svg:, fit: 'stretch')
      encoded = Base64.strict_encode64(svg.to_s)
      {
        'id' => required_string(id, 'image id'),
        'kind' => 'image',
        'source' => {'kind' => 'url', 'url' => "data:image/svg+xml;base64,#{encoded}"},
        'style' => {'fit' => fit, 'padding' => 'none'}
      }
    end

    def band_image(id:, text:, width:, height:, background: nil, foreground: '#FFFFFF', font_size: 14)
      pixel_width = (width.to_f * 2).round
      pixel_height = (height.to_f * 2).round
      safe_text = CGI.escapeHTML(text.to_s)
      svg = <<~SVG
        <svg xmlns="http://www.w3.org/2000/svg" width="#{pixel_width}" height="#{pixel_height}" viewBox="0 0 #{pixel_width} #{pixel_height}">
          <rect width="#{pixel_width}" height="#{pixel_height}" rx="8" fill="#{background || brand['primary']}"/>
          <text x="#{pixel_width / 2}" y="#{pixel_height / 2}" font-family="Arial, sans-serif"
                font-size="#{font_size * 2}" font-weight="700" fill="#{foreground}"
                text-anchor="middle" dominant-baseline="middle">#{safe_text}</text>
        </svg>
      SVG
      svg_image(id: id, svg: svg)
    end

    def sql_table(id:, name:, connection_id:, statement:, columns:)
      {
        'id' => required_string(id, 'SQL table id'),
        'kind' => 'table',
        'name' => required_string(name, 'SQL table name'),
        'source' => {
          'kind' => 'sql',
          'connectionId' => required_string(connection_id, 'connection_id'),
          'statement' => required_string(statement, 'SQL statement')
        },
        'columns' => Array(columns).each_with_index.map do |column, index|
          column = {'name' => column} if column.is_a?(String)
          name = required_string(column['name'], "column #{index} name")
          out = {
            'id' => column['id'] || "#{id}-c#{index + 1}",
            'name' => name,
            'formula' => column['formula'] || "[Custom SQL/#{name}]"
          }
          out['format'] = column['format'] if column['format']
          out['hidden'] = true if column['hidden']
          out
        end
      }
    end

    def kpi(id:, source_id:, label:, value_formula:, format: nil, comparison_formula: nil,
            direction: 'higher', comparison_display: 'percentage', font_size: 24)
      columns = [
        {
          'id' => "#{id}-value",
          'name' => label,
          'formula' => value_formula
        }
      ]
      columns[0]['format'] = format if format
      element = {
        'id' => id,
        'kind' => 'kpi-chart',
        'name' => {'text' => label, 'color' => brand['muted'], 'fontSize' => 11},
        'source' => {'kind' => 'table', 'elementId' => source_id},
        'columns' => columns,
        'value' => {
          'columnId' => "#{id}-value",
          'color' => brand['ink'],
          'fontSize' => font_size,
          'fontWeight' => 'bold'
        },
        'layout' => {'anchor' => 'left', 'verticalAnchor' => 'top', 'titleOrient' => 'top'},
        'style' => {
          'backgroundColor' => '#FFFFFF',
          'borderColor' => brand['line'],
          'borderWidth' => 1,
          'borderRadius' => 'round'
        }
      }
      if comparison_formula
        columns << {
          'id' => "#{id}-comparison",
          'name' => 'Comparison',
          'formula' => comparison_formula,
          'format' => format
        }.compact
        element['comparisonColumn'] = {'columnId' => "#{id}-comparison"}
        element['comparison'] = {
          'display' => comparison_display,
          'direction' => direction,
          'colorGood' => brand['success'],
          'colorBad' => brand['danger'],
          'colorNeutral' => brand['muted']
        }
      end
      element
    end

    def computed_row(widths:, gap:, left: 0, right: nil)
      widths = Array(widths).map { |width| positive_number(width, 'row width') }
      gap = nonnegative_number(gap, 'row gap')
      right ||= page_width
      required = widths.sum + (gap * [widths.length - 1, 0].max)
      available = right - left
      raise ArgumentError, "row needs #{required}px but only #{available}px is available" if required > available

      x = left
      widths.map do |width|
        current = x
        x += width + gap
        current
      end
    end

    def to_h(description: nil)
      contents['layout'] = render_layout
      out = {'name' => name, 'folderId' => folder_id}
      out['description'] = description if description
      out['contents'] = contents
      out
    end

    def to_json(**options)
      JSON.pretty_generate(to_h, **options)
    end

    private

    def register_region(id, tag, type = nil)
      id = required_string(id, "#{tag} id")
      raise ArgumentError, "duplicate region id #{id.inspect}" if @regions[id]

      @regions[id] = {'tag' => tag, 'type' => type, 'placements' => []}
      id
    end

    def render_layout
      lines = ['<?xml version="1.0" encoding="utf-8"?>']
      (@pages.map { |page| page['id'] } + @panels.map { |panel| panel['id'] }).each do |id|
        region = @regions.fetch(id)
        attrs = %(id="#{id}")
        attrs += %( type="#{region['type']}") if region['type']
        lines << "<#{region['tag']} #{attrs}>"
        region['placements'].each do |rect|
          lines << %(  <Element elementId="#{rect['elementId']}" x="#{rect['x']}" y="#{rect['y']}" width="#{rect['width']}" height="#{rect['height']}"/>)
        end
        lines << "</#{region['tag']}>"
      end
      lines.join("\n")
    end

    def stringify_keys(hash)
      hash.to_h.each_with_object({}) { |(key, value), out| out[key.to_s] = value }
    end

    def required_string(value, label)
      raise ArgumentError, "#{label} is required" unless value.is_a?(String) && !value.strip.empty?

      value
    end

    def positive_number(value, label)
      parsed = Float(value)
      raise ArgumentError, "#{label} must be positive" unless parsed.finite? && parsed.positive?

      parsed % 1 == 0 ? parsed.to_i : parsed
    rescue ArgumentError, TypeError
      raise ArgumentError, "#{label} must be positive"
    end

    def nonnegative_number(value, label)
      parsed = Float(value)
      raise ArgumentError, "#{label} must be non-negative" unless parsed.finite? && !parsed.negative?

      parsed % 1 == 0 ? parsed.to_i : parsed
    rescue ArgumentError, TypeError
      raise ArgumentError, "#{label} must be non-negative"
    end
  end
end
