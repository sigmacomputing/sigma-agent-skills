#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'optparse'
require 'cgi'
require_relative 'lib/report_builder'
require_relative 'lib/report_spec_validator'

MONEY = {'kind' => 'number', 'formatString' => '$.3s'}.freeze
MONEY0 = {'kind' => 'number', 'formatString' => '$,.0f'}.freeze
NUMBER0 = {'kind' => 'number', 'formatString' => ',.0f'}.freeze
PERCENT = {'kind' => 'number', 'formatString' => ',.1%'}.freeze

def source_columns(source_name, definitions)
  definitions.map.with_index do |(name, format, hidden), index|
    column = {
      'id' => "#{source_name.downcase.gsub(/[^a-z0-9]+/, '-')}-#{index + 1}",
      'name' => name,
      'formula' => "[Custom SQL/#{name}]"
    }
    column['format'] = format if format
    column['hidden'] = true if hidden
    column
  end
end

def derived_columns(source_name, definitions)
  definitions.map.with_index do |(name, format, hidden), index|
    column = {
      'id' => "view-#{source_name.downcase.gsub(/[^a-z0-9]+/, '-')}-#{index + 1}",
      'name' => name,
      'formula' => "[#{source_name}/#{name}]"
    }
    column['format'] = format if format
    column['hidden'] = true if hidden
    column
  end
end

def place_title(builder, page, id, title, subtitle = nil)
  builder.place(
    builder.text(id: "#{id}-title", body: "**#{title}**", color: builder.brand['ink'], font_size: 27),
    region: page, x: 0, y: 0, width: builder.content_width, height: 44
  )
  return unless subtitle

  builder.place(
    builder.text(id: "#{id}-subtitle", body: subtitle, color: builder.brand['muted'], font_size: 11),
    region: page, x: 0, y: 48, width: builder.content_width, height: 36
  )
end

def install_furniture(builder, visible_pages, company, report_label)
  builder.add_panel(id: 'global-header', type: 'header', height: 56, pages: visible_pages)
  builder.add_panel(id: 'global-footer', type: 'footer', height: 40, pages: visible_pages)
  builder.place(
    builder.text(id: 'header-company', body: "**#{company}**", color: builder.brand['primary'], font_size: 18),
    region: 'global-header', x: builder.margin, y: 10, width: 300, height: 30
  )
  builder.place(
    builder.text(id: 'header-report', body: report_label, color: builder.brand['muted'], font_size: 9, align: 'right'),
    region: 'global-header', x: builder.page_width - builder.margin - 300, y: 16, width: 300, height: 20
  )
  builder.place(
    {'id' => 'header-rule', 'kind' => 'divider', 'style' => {'color' => builder.brand['primary']}},
    region: 'global-header', x: builder.margin, y: 48, width: builder.content_width, height: 2
  )
  builder.place(
    builder.text(
      id: 'footer-note',
      body: "#{company} — confidential — generated from the approved report data contract.",
      color: builder.brand['muted'],
      font_size: 9
    ),
    region: 'global-footer', x: builder.margin, y: 10, width: builder.content_width, height: 22
  )
end

def board_report(name:, folder_id:, connection_id:, company:)
  builder = ReportSpec::Builder.new(name: name, folder_id: folder_id, paper: 'letter-portrait', margin: 30)
  visible_pages = %w[p1 p2 p3 p4 p5]
  [
    ['p1', 'Executive highlights'],
    ['p2', 'Scorecard'],
    ['p3', 'Trend and segment performance'],
    ['p4', 'Performance bridge'],
    ['p5', 'Operational drill-down']
  ].each { |id, page_name| builder.add_page(id: id, name: page_name) }
  builder.add_page(id: 'pdata', name: 'Data', hidden: true)
  install_furniture(builder, visible_pages, company, 'QUARTERLY BUSINESS REVIEW')

  summary_columns = [
    ['current_sales', MONEY, false],
    ['prior_sales', MONEY, false],
    ['current_margin', PERCENT, false],
    ['prior_margin', PERCENT, false],
    ['current_ebit', MONEY, false],
    ['prior_ebit', MONEY, false],
    ['traffic', NUMBER0, false],
    ['transactions', NUMBER0, false],
    ['headcount', NUMBER0, false],
    ['prior_headcount', NUMBER0, false]
  ]
  summary_sql = <<~SQL
    SELECT
      102000000::NUMBER AS "current_sales",
      99000000::NUMBER AS "prior_sales",
      0.466::FLOAT AS "current_margin",
      0.457::FLOAT AS "prior_margin",
      5880000::NUMBER AS "current_ebit",
      4780000::NUMBER AS "prior_ebit",
      4030000::NUMBER AS "traffic",
      1050000::NUMBER AS "transactions",
      331::NUMBER AS "headcount",
      250::NUMBER AS "prior_headcount"
  SQL
  summary = builder.sql_table(
    id: 'src-summary', name: 'Summary', connection_id: connection_id,
    statement: summary_sql, columns: source_columns('Summary', summary_columns)
  )
  builder.place(summary, region: 'pdata', x: 0, y: 0, width: builder.content_width, height: 160)

  trend_columns = [
    ['quarter', nil, false],
    ['sales', MONEY, false],
    ['segment', nil, false],
    ['growth', PERCENT, false]
  ]
  trend_sql = <<~SQL
    SELECT * FROM VALUES
      ('FY2025-Q1', 23000000, 'Core', 0.030),
      ('FY2025-Q2', 25000000, 'Core', 0.034),
      ('FY2025-Q3', 24900000, 'Growth', 0.023),
      ('FY2025-Q4', 28900000, 'Growth', 0.031),
      ('FY2026-Q1', 23500000, 'Latest', 0.018)
      AS v("quarter", "sales", "segment", "growth")
  SQL
  trend = builder.sql_table(
    id: 'src-trend', name: 'Trend', connection_id: connection_id,
    statement: trend_sql, columns: source_columns('Trend', trend_columns)
  )
  builder.place(trend, region: 'pdata', x: 0, y: 170, width: builder.content_width, height: 180)

  bridge_columns = [
    ['step_order', NUMBER0, false],
    ['label', nil, false],
    ['delta', MONEY, false],
    ['prior_total', MONEY, false],
    ['current_total', MONEY, false]
  ]
  bridge_sql = <<~SQL
    SELECT * FROM VALUES
      (1, 'Accessories', 60000, 573000, 793000),
      (2, 'Apparel', 93000, 573000, 793000),
      (3, 'Footwear', 95000, 573000, 793000),
      (4, 'Corporate G&A', -28000, 573000, 793000)
      AS v("step_order", "label", "delta", "prior_total", "current_total")
  SQL
  bridge = builder.sql_table(
    id: 'src-bridge', name: 'Bridge', connection_id: connection_id,
    statement: bridge_sql, columns: source_columns('Bridge', bridge_columns)
  )
  builder.place(bridge, region: 'pdata', x: 0, y: 360, width: builder.content_width, height: 180)

  detail_columns = [
    ['group_name', nil, false],
    ['location', nil, false],
    ['sales', MONEY, false],
    ['growth', PERCENT, false],
    ['sort_order', NUMBER0, true]
  ]
  detail_sql = <<~SQL
    SELECT * FROM VALUES
      ('Top locations', 'Location A', 1090000, 0.141, 1),
      ('Top locations', 'Location B', 813000, 0.089, 2),
      ('Bottom locations', 'Location C', 990000, -0.096, 3),
      ('Bottom locations', 'Location D', 670000, -0.020, 4)
      AS v("group_name", "location", "sales", "growth", "sort_order")
  SQL
  detail = builder.sql_table(
    id: 'src-detail', name: 'Detail', connection_id: connection_id,
    statement: detail_sql, columns: source_columns('Detail', detail_columns)
  )
  builder.place(detail, region: 'pdata', x: 0, y: 550, width: builder.content_width, height: 180)

  # Page 1 — asymmetric cover + KPI row + narrative.
  hero_svg = <<~SVG
    <svg xmlns="http://www.w3.org/2000/svg" width="672" height="1700" viewBox="0 0 672 1700">
      <defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0%" stop-color="#0A2E70"/><stop offset="100%" stop-color="#3D8BFF"/>
      </linearGradient></defs>
      <rect width="672" height="1700" rx="36" fill="url(#g)"/>
      <g stroke="#FFFFFF" stroke-opacity=".12" fill="none">
        <circle cx="520" cy="300" r="180"/><circle cx="520" cy="300" r="300"/>
      </g>
      <text x="72" y="1230" fill="#FFFFFF" font-family="Arial" font-size="62" font-weight="700">#{CGI.escapeHTML(company)}</text>
      <text x="72" y="1300" fill="#DCE6FE" font-family="Arial" font-size="27">Executive performance review</text>
    </svg>
  SVG
  builder.place(builder.svg_image(id: 'p1-hero', svg: hero_svg, fit: 'cover'),
                region: 'p1', x: 0, y: 0, width: 326, height: 850)
  builder.place(builder.text(id: 'p1-title', body: '**Full year highlights**', font_size: 27),
                region: 'p1', x: 350, y: 0, width: 406, height: 48)
  builder.place(builder.text(id: 'p1-sub', body: 'TRAILING TWELVE MONTHS VS. PRIOR PERIOD',
                             color: builder.brand['muted'], font_size: 10),
                region: 'p1', x: 350, y: 52, width: 406, height: 22)
  kpi_width = 126
  [350, 490, 630].zip([
    ['p1-sales', 'Net sales', 'Sum([Summary/current_sales])', 'Sum([Summary/prior_sales])', MONEY],
    ['p1-margin', 'Gross margin', 'Sum([Summary/current_margin])', 'Sum([Summary/prior_margin])', PERCENT],
    ['p1-ebit', 'EBIT', 'Sum([Summary/current_ebit])', 'Sum([Summary/prior_ebit])', MONEY]
  ]).each do |x, (id, label, current, prior, format)|
    builder.place(builder.kpi(id: id, source_id: 'src-summary', label: label,
                              value_formula: current, comparison_formula: prior, format: format),
                  region: 'p1', x: x, y: 82, width: kpi_width, height: 126)
  end
  builder.place(builder.text(id: 'p1-moves', body: '**KEY MOVES**', color: builder.brand['primary'], font_size: 12),
                region: 'p1', x: 350, y: 236, width: 406, height: 24)
  [
    'Sales increased versus the prior period while profitability remained resilient.',
    'Margin movement should be read with product and channel mix.',
    'The latest quarter remains positive but trails the full-year pace.',
    'Headcount increased to support growth and operating complexity.',
    'Use the drill-down pages to isolate location and segment outliers.'
  ].each_with_index do |line, index|
    builder.place(builder.text(id: "p1-note-#{index + 1}", body: line, color: builder.brand['ink'], font_size: 16),
                  region: 'p1', x: 350, y: 278 + (index * 104), width: 406, height: 82)
  end

  # Page 2 — three scorecard columns with computed, non-overlapping geometry.
  place_title(builder, 'p2', 'p2', 'Financial and operating highlights',
              'TRAILING TWELVE MONTHS VS. THE PRIOR TWELVE MONTHS')
  band_width = 236
  band_x = builder.computed_row(widths: [band_width, band_width, band_width], gap: 24,
                                left: 0, right: builder.content_width)
  %w[SALES\ \&\ EARNINGS PROFITABILITY\ \&\ OPERATIONS CUSTOMER,\ TEAM\ \&\ CHANNEL].each_with_index do |label, index|
    builder.place(builder.band_image(id: "p2-band-#{index + 1}", text: label.tr('\\', ''),
                                     width: band_width, height: 30),
                  region: 'p2', x: band_x[index], y: 90, width: band_width, height: 30)
  end
  scorecards = [
    ['Net sales', 'Sum([Summary/current_sales])', 'Sum([Summary/prior_sales])', MONEY],
    ['Gross margin', 'Sum([Summary/current_margin])', 'Sum([Summary/prior_margin])', PERCENT],
    ['Traffic', 'Sum([Summary/traffic])', '0', NUMBER0],
    ['EBIT', 'Sum([Summary/current_ebit])', 'Sum([Summary/prior_ebit])', MONEY],
    ['EBIT margin', 'Sum([Summary/current_ebit]) / Sum([Summary/current_sales])',
     'Sum([Summary/prior_ebit]) / Sum([Summary/prior_sales])', PERCENT],
    ['Transactions', 'Sum([Summary/transactions])', '0', NUMBER0],
    ['Sales growth', 'Sum([Summary/current_sales]) / Sum([Summary/prior_sales]) - 1', '0', PERCENT],
    ['Margin delta', 'Sum([Summary/current_margin])', 'Sum([Summary/prior_margin])', PERCENT],
    ['Conversion', 'Sum([Summary/transactions]) / Sum([Summary/traffic])', '0', PERCENT],
    ['Current headcount', 'Sum([Summary/headcount])', 'Sum([Summary/prior_headcount])', NUMBER0],
    ['Prior headcount', 'Sum([Summary/prior_headcount])', '0', NUMBER0],
    ['Sales per employee', 'Sum([Summary/current_sales]) / Sum([Summary/headcount])', '0', MONEY]
  ]
  scorecards.each_with_index do |(label, current, prior, format), index|
    column = index % 3
    row = index / 3
    builder.place(builder.kpi(id: "p2-kpi-#{index + 1}", source_id: 'src-summary', label: label,
                              value_formula: current, comparison_formula: prior, format: format, font_size: 21),
                  region: 'p2', x: band_x[column], y: 132 + (row * 108), width: band_width, height: 94)
  end

  # Page 3 — chart + table.
  place_title(builder, 'p3', 'p3', 'Momentum and segment performance',
              'FIVE CLOSED QUARTERS WITH SEGMENT GROWTH')
  bar = {
    'id' => 'p3-bar', 'kind' => 'bar-chart',
    'source' => {'kind' => 'table', 'elementId' => 'src-trend'},
    'columns' => [
      {'id' => 'p3-quarter', 'name' => 'Quarter', 'formula' => '[Trend/quarter]'},
      {'id' => 'p3-sales', 'name' => 'Sales', 'formula' => 'Sum([Trend/sales])', 'format' => MONEY},
      {'id' => 'p3-color', 'name' => 'Segment', 'formula' => '[Trend/segment]'}
    ],
    'xAxis' => {'columnId' => 'p3-quarter'},
    'yAxis' => {'columnIds' => ['p3-sales']},
    'color' => {'by' => 'category', 'column' => 'p3-color', 'scheme' => [builder.brand['primary'], '#DCE6FE']},
    'name' => {'visibility' => 'hidden'}, 'legend' => {'visibility' => 'hidden'},
    'style' => {'backgroundColor' => '#FFFFFF', 'borderColor' => builder.brand['line'], 'borderWidth' => 1}
  }
  builder.place(bar, region: 'p3', x: 0, y: 100, width: 320, height: 580)
  trend_table = {
    'id' => 'p3-table', 'kind' => 'table',
    'source' => {'kind' => 'table', 'elementId' => 'src-trend'},
    'columns' => derived_columns('Trend', trend_columns),
    'order' => %w[view-trend-3 view-trend-1 view-trend-4],
    'tableComponents' => {'summaryBar' => 'hidden'},
    'tableStyle' => {'preset' => 'presentation', 'cellSpacing' => 'medium'},
    'name' => {'visibility' => 'hidden'},
    'style' => {'backgroundColor' => '#FFFFFF', 'borderColor' => builder.brand['line'], 'borderWidth' => 1}
  }
  builder.place(trend_table, region: 'p3', x: 344, y: 100, width: 412, height: 580)

  # Page 4 — waterfall plus KPI rail.
  place_title(builder, 'p4', 'p4', 'Performance bridge', 'LATEST PERIOD VS. PRIOR COMPARABLE PERIOD')
  [
    ['Accessories', 'SumIf([Bridge/delta], [Bridge/label] = "Accessories")'],
    ['Apparel', 'SumIf([Bridge/delta], [Bridge/label] = "Apparel")'],
    ['Footwear', 'SumIf([Bridge/delta], [Bridge/label] = "Footwear")'],
    ['Corporate G&A', 'SumIf([Bridge/delta], [Bridge/label] = "Corporate G&A")'],
    ['Current total', 'Max([Bridge/current_total])']
  ].each_with_index do |(label, formula), index|
    builder.place(builder.kpi(id: "p4-kpi-#{index + 1}", source_id: 'src-bridge',
                              label: label, value_formula: formula, format: MONEY),
                  region: 'p4', x: 0, y: 90 + (index * 126), width: 194, height: 112)
  end
  waterfall = {
    'id' => 'p4-waterfall', 'kind' => 'waterfall-chart',
    'source' => {'kind' => 'table', 'elementId' => 'src-bridge'},
    'columns' => [
      {'id' => 'bridge-label', 'name' => 'Step', 'formula' => '[Bridge/label]'},
      {'id' => 'bridge-order', 'name' => 'Order', 'formula' => '[Bridge/step_order]'},
      {'id' => 'bridge-delta', 'name' => 'Change', 'formula' => 'Sum([Bridge/delta])', 'format' => MONEY},
      {'id' => 'bridge-prior', 'name' => 'Prior', 'formula' => 'Max([Bridge/prior_total])', 'format' => MONEY}
    ],
    'xAxis' => {'columnId' => 'bridge-label',
                'sort' => {'by' => 'bridge-order', 'direction' => 'ascending'}},
    'yAxis' => {'columnIds' => ['bridge-delta']},
    'waterfallColors' => {
      'increase' => builder.brand['success'],
      'decrease' => builder.brand['danger'],
      'total' => builder.brand['deep']
    },
    'waterfallShape' => {'calculation' => 'sum', 'connectorLine' => 'shown',
                         'connectorLineColor' => builder.brand['line']},
    'startPoint' => {
      'label' => 'Prior total',
      'value' => {'type' => 'column', 'columnId' => 'bridge-prior', 'func' => 'max'}
    },
    'name' => {'visibility' => 'hidden'}, 'legend' => {'visibility' => 'hidden'},
    'style' => {'backgroundColor' => '#FFFFFF', 'borderColor' => builder.brand['line'], 'borderWidth' => 1}
  }
  builder.place(waterfall, region: 'p4', x: 218, y: 90, width: 538, height: 616)

  # Page 5 — summary cards + exception detail.
  place_title(builder, 'p5', 'p5', 'Operational drill-down',
              'TOP AND BOTTOM LOCATIONS BY YEAR-OVER-YEAR PERFORMANCE')
  [0, 1, 2].each do |index|
    label, formula, comparison = [
      ['Sales', 'Sum([Summary/current_sales])', 'Sum([Summary/prior_sales])'],
      ['Margin', 'Sum([Summary/current_margin])', 'Sum([Summary/prior_margin])'],
      ['Headcount', 'Sum([Summary/headcount])', 'Sum([Summary/prior_headcount])']
    ][index]
    builder.place(builder.kpi(id: "p5-kpi-#{index + 1}", source_id: 'src-summary', label: label,
                              value_formula: formula, comparison_formula: comparison,
                              format: index == 1 ? PERCENT : (index == 2 ? NUMBER0 : MONEY)),
                  region: 'p5', x: index * 260, y: 90, width: 236, height: 112)
  end
  detail_table = {
    'id' => 'p5-table', 'kind' => 'table',
    'source' => {'kind' => 'table', 'elementId' => 'src-detail'},
    'columns' => derived_columns('Detail', detail_columns),
    'sort' => [{'columnId' => 'view-detail-5', 'direction' => 'ascending'}],
    'order' => %w[view-detail-1 view-detail-2 view-detail-3 view-detail-4],
    'conditionalFormats' => [
      {'type' => 'single', 'columnIds' => ['view-detail-4'], 'condition' => '<', 'value' => 0,
       'style' => {'color' => builder.brand['danger'], 'backgroundColor' => 'transparent'}}
    ],
    'tableComponents' => {'summaryBar' => 'hidden'},
    'tableStyle' => {'preset' => 'presentation', 'cellSpacing' => 'small'},
    'name' => {'visibility' => 'hidden'},
    'style' => {'backgroundColor' => '#FFFFFF', 'borderColor' => builder.brand['line'], 'borderWidth' => 1}
  }
  builder.place(detail_table, region: 'p5', x: 0, y: 234, width: 756, height: 520)

  builder.to_h(description: 'Five-page executive board-report scaffold with synthetic data contracts')
end

def wide_table_report(name:, folder_id:, connection_id:, company:)
  builder = ReportSpec::Builder.new(name: name, folder_id: folder_id, paper: 'tabloid-landscape', margin: 50)
  visible_pages = %w[p1 p2 p3 p4]
  visible_pages.each_with_index { |id, index| builder.add_page(id: id, name: "Inventory #{index + 1}") }
  builder.add_page(id: 'pdata', name: 'Data', hidden: true)
  install_furniture(builder, visible_pages, company, 'WIDE OPERATIONAL INVENTORY ANALYSIS')

  columns = [
    ['code', nil, false], ['dealer', nil, false],
    ['units_1', NUMBER0, false], ['dollars_1', MONEY0, false],
    ['units_2', NUMBER0, false], ['dollars_2', MONEY0, false],
    ['change', MONEY0, false],
    ['month_1', MONEY0, false], ['month_2', MONEY0, false],
    ['month_3', MONEY0, false], ['three_month_avg', MONEY0, false],
    ['turns_monthly', NUMBER0, false], ['annualized_turns', NUMBER0, false],
    ['days_supply', NUMBER0, false], ['fleet_units', NUMBER0, false],
    ['fleet_days', NUMBER0, false], ['page_no', NUMBER0, true]
  ]
  sql = <<~SQL
    SELECT * FROM VALUES
      ('A001', 'Location One', 12, 450000, 14, 510000, 60000, 2000000, 3000000, 2500000, 2500000, 2.2, 26.4, 41, 3, 19, 1),
      ('A002', 'Location Two', 8, 325000, 10, 390000, 65000, 1800000, 2200000, 2100000, 2033333, 1.8, 21.6, 52, 2, 24, 1),
      ('TOTAL A', 'TOTAL BRAND A', 20, 775000, 24, 900000, 125000, 3800000, 5200000, 4600000, 4533333, 2.0, 24.0, 46, 5, 22, 1),
      ('B001', 'Location Three', 9, 400000, 11, 475000, 75000, 1900000, 2400000, 2300000, 2200000, 1.9, 22.8, 48, 1, 12, 2),
      ('TOTAL B', 'TOTAL BRAND B', 9, 400000, 11, 475000, 75000, 1900000, 2400000, 2300000, 2200000, 1.9, 22.8, 48, 1, 12, 2),
      ('C001', 'Location Four', 7, 300000, 9, 360000, 60000, 1700000, 2100000, 2000000, 1933333, 1.7, 20.4, 55, 0, 0, 3),
      ('TOTAL C', 'TOTAL BRAND C', 7, 300000, 9, 360000, 60000, 1700000, 2100000, 2000000, 1933333, 1.7, 20.4, 55, 0, 0, 3),
      ('D001', 'Location Five', 15, 600000, 18, 720000, 120000, 2600000, 3100000, 2900000, 2866667, 2.5, 30.0, 36, 4, 18, 4),
      ('TOTAL D', 'TOTAL BRAND D', 15, 600000, 18, 720000, 120000, 2600000, 3100000, 2900000, 2866667, 2.5, 30.0, 36, 4, 18, 4)
      AS v("code", "dealer", "units_1", "dollars_1", "units_2", "dollars_2",
           "change", "month_1", "month_2", "month_3", "three_month_avg",
           "turns_monthly", "annualized_turns", "days_supply",
           "fleet_units", "fleet_days", "page_no")
  SQL
  source = builder.sql_table(
    id: 'src-inventory', name: 'Inventory', connection_id: connection_id,
    statement: sql, columns: source_columns('Inventory', columns)
  )
  builder.place(source, region: 'pdata', x: 0, y: 0, width: builder.content_width, height: 900)

  band_specs = [
    ['New vehicle inventory', 390, '#DCE6F0'],
    ['Retail and fleet cost of sales', 570, '#E8F0D9'],
    ['Turns and days supply', 310, '#FFF5D6'],
    ['Commercial / fleet', 212, '#EEE7F6']
  ]
  x_positions = builder.computed_row(
    widths: band_specs.map { |spec| spec[1] }, gap: 16, left: 0, right: builder.content_width
  )
  visible_pages.each_with_index do |page_id, page_index|
    band_specs.each_with_index do |(label, width, color), index|
      builder.place(
        builder.band_image(
          id: "#{page_id}-band-#{index + 1}", text: label.upcase,
          width: width, height: 36, background: color, foreground: builder.brand['ink'], font_size: 11
        ),
        region: page_id, x: x_positions[index], y: 0, width: width, height: 36
      )
    end
    table_columns = derived_columns('Inventory', columns)
    table_columns[-1]['hidden'] = true
    table = {
      'id' => "#{page_id}-table", 'kind' => 'table',
      'source' => {'kind' => 'table', 'elementId' => 'src-inventory'},
      'columns' => table_columns,
      'filters' => [
        {
          'id' => "#{page_id}-filter", 'kind' => 'list', 'columnId' => 'view-inventory-17',
          'mode' => 'include', 'values' => [page_index + 1]
        }
      ],
      'order' => (1..16).map { |index| "view-inventory-#{index}" },
      'tableComponents' => {'summaryBar' => 'hidden'},
      'tableStyle' => {'preset' => 'presentation', 'cellSpacing' => 'extra-small',
                       'gridLines' => 'all', 'banding' => 'hidden'},
      'name' => {'visibility' => 'hidden'},
      'style' => {'backgroundColor' => '#FFFFFF', 'borderColor' => builder.brand['line'], 'borderWidth' => 1}
    }
    # Keep the box proportional to the page slice's expected rows. An
    # over-tall table can be treated as "expanded" by PDF export and moved to
    # a separate continuation page, leaving the authored band page empty.
    builder.place(table, region: page_id, x: 0, y: 48, width: builder.content_width, height: 320)
  end

  builder.to_h(description: 'Four-page tabloid-landscape operational table scaffold with explicit page slices')
end

options = {
  template: 'board',
  name: 'Generated Report',
  folder_id: '<folder-id>',
  connection_id: '<connection-id>',
  company: 'ACME',
  output: '/tmp/report-scaffold.json'
}
OptionParser.new do |parser|
  parser.banner = 'Usage: ruby scripts/scaffold-report.rb [options]'
  parser.on('--template NAME', %w[board wide-table], 'board or wide-table') { |value| options[:template] = value }
  parser.on('--name NAME', 'Report name') { |value| options[:name] = value }
  parser.on('--folder-id ID', 'Destination folder UUID') { |value| options[:folder_id] = value }
  parser.on('--connection-id ID', 'Warehouse connection UUID') { |value| options[:connection_id] = value }
  parser.on('--company NAME', 'Brand/company label') { |value| options[:company] = value }
  parser.on('-o', '--output PATH', 'Output JSON path') { |value| options[:output] = value }
end.parse!

spec = case options[:template]
       when 'board'
         board_report(
           name: options[:name], folder_id: options[:folder_id],
           connection_id: options[:connection_id], company: options[:company]
         )
       when 'wide-table'
         wide_table_report(
           name: options[:name], folder_id: options[:folder_id],
           connection_id: options[:connection_id], company: options[:company]
         )
       end

validation = ReportSpec::Validator.new(spec, mode: :create).validate
unless validation.valid?
  warn validation.errors.map { |error| "ERROR: #{error}" }
  abort 'scaffold generated an invalid report'
end
File.write(options[:output], JSON.pretty_generate(spec))
puts "wrote #{options[:template]} scaffold to #{options[:output]} " \
     "(#{spec.dig('contents', 'pages').length} pages, #{spec.dig('contents', 'elements').length} elements, " \
     "#{validation.warnings.length} warning(s))"
