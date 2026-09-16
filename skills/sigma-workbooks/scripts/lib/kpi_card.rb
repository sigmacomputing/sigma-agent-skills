# frozen_string_literal: true
#
# kpi_card.rb — emits the VERIFIED comparative KPI-card shape: a kpi-chart
# element with a value column AND a comparison column rendered as a Δ badge.
# Documented as the house default for KPI cards in this skill (see
# reference/specification/comparative-kpi-card.yaml and
# reference/workflows/composition.md's "Richness" section).
#
#   require_relative 'lib/kpi_card'
#   el = KpiCard.build(id: 'kpi-rev', name: 'Revenue', source_element_id: 'tbl-1',
#                      columns: [{'id'=>'rev_cur'}], value_column_id: 'rev_cur',
#                      comparison_column_id: 'rev_prior', good_direction: :up)
#
# This emitter builds ONLY the kpi-chart element (a Hash) — not a whole
# workbook, container, or layout — so it drops cleanly into any builder that
# lays out elements separately. Number/percent formatting is a COLUMN concern,
# not a value concern: pass it on the relevant columns[] entry, e.g.
# {'id'=>'rev_cur','format'=>{'kind'=>'number','formatString'=>'$,.0f'}} — it
# rides through the columns passthrough untouched.
#
# Stdlib only (json); Ruby 2.6+-compatible. Golden-tested output lives in
# scripts/lib/testdata/kpi_card_golden.json and
# kpi_card_value_style_golden.json (see test_kpi_card.rb).

require 'json'

module KpiCard
  DELTA_GOOD = '#1a7f37' # green
  DELTA_BAD  = '#cf222e' # red

  # Returns a kpi-chart element Hash. comparison_column_id nil/'' ⇒ single-value
  # card (no comparison/comparisonColumn keys). Callers may layer tool-specific
  # decorations (font overrides, extra columns) onto the returned Hash.
  #
  # value_color:/value_font_size: are optional accent styling for the value
  # itself (verified GO shape: value:{columnId,color,fontSize}). Both nil
  # (the default) ⇒ value is just {'columnId'=>...}, byte-identical to before
  # these kwargs existed.
  def self.build(id:, name:, source_element_id:, columns:, value_column_id:,
                 comparison_column_id: nil,
                 good_direction: :up, title_color: nil,
                 value_color: nil, value_font_size: nil)
    raise ArgumentError, 'id required' if id.to_s.empty?
    raise ArgumentError, 'value_column_id required' if value_column_id.to_s.empty?

    cols = (columns || []).map { |c| c }
    has_cmp = comparison_column_id && !comparison_column_id.to_s.empty?
    if has_cmp && cols.none? { |c| c['id'].to_s == comparison_column_id.to_s }
      cols = cols + [{ 'id' => comparison_column_id }]
    end

    name_obj = { 'text' => name }
    name_obj['color'] = title_color if title_color

    value = { 'columnId' => value_column_id }
    value['color'] = value_color unless value_color.nil?
    value['fontSize'] = value_font_size unless value_font_size.nil?

    el = {
      'id'      => id,
      'kind'    => 'kpi-chart',
      'name'    => name_obj,
      'source'  => { 'kind' => 'table', 'elementId' => source_element_id },
      'columns' => cols,
      'value'   => value
    }

    if has_cmp
      up = good_direction.to_sym == :up
      el['comparisonColumn'] = { 'columnId' => comparison_column_id }
      el['comparison'] = {
        'display'   => 'delta',
        'colorGood' => up ? DELTA_GOOD : DELTA_BAD,
        'colorBad'  => up ? DELTA_BAD : DELTA_GOOD
      }
    end
    el
  end
end
