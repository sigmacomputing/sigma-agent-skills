# shared/lib/code_rep.rb
# Shape adapter for the Sigma WORKBOOK code representation
# (GET /v2/workbooks/{id}?includeContents=true, POST /v2/workbooks,
# PUT /v2/workbooks/{id}/contents). The legacy /v2/workbooks/spec* family is
# gone from this adapter entirely -- Sigma is launching the contents-based
# surface as the recommended path and /spec remains supported server-side,
# but this skill's tooling always writes and expects the new shape.
#
# This surface nests non-metadata fields under a top-level `contents` key
# (the legacy /spec endpoints used `document`). Reads stay tolerant of both
# `contents` and the legacy `document` key because committed on-disk
# snapshots/fixtures written before the migration still use `document`, and
# of the pre-both flat shape for even older artifacts.
#
# Sigma engineering confirmed 2026-08-03 that the DATA-MODEL code-rep surface
# is NOT part of this migration, so this adapter is deliberately workbook-only.
# Do NOT use it on /v2/dataModels/.../spec payloads — that API ignores
# `contents`/`document` and will 400 on a missing top-level `schemaVersion`.
module Sigma
  module CodeRep
    # Every field accepted inside `document` by the live workbook OpenAPI.
    # `elements` is a required flat array; pages/overlays/panels are metadata
    # collections whose membership is established by `layout`, not by nested
    # element arrays. Keep this list complete: an omitted key is misclassified
    # as outer metadata and is then silently dropped from PUT bodies.
    DOC_KEYS = %w[
      schemaVersion kind elements pages overlays panels layout settings agents
    ].freeze

    # REMOVED from the API. The workbook theme is now `settings.theme.name` and
    # `settings.theme.overrides` (published OpenAPI: createWorkbookSpec — there
    # are zero occurrences of themeName/themeOverrides in it). The individual
    # override keys are unchanged (categoricalScheme, colorOverrides, hasCards,
    # borderRadius, elementBorder, titleFont, tableStyles, …) — only the
    # container path moved. document() folds the legacy pair forward so specs
    # and fixtures written before the move still produce a valid body.
    LEGACY_THEME_KEYS = %w[themeName themeOverrides].freeze
    CANONICAL_LAYOUT_NODE_TAGS = %w[Element Container TabbedContainer].freeze
    LEGACY_LAYOUT_NODE_TAGS = %w[LayoutElement GridContainer].freeze
    LAYOUT_NODE_TAG_PATTERN = (
      CANONICAL_LAYOUT_NODE_TAGS + LEGACY_LAYOUT_NODE_TAGS
    ).join('|').freeze

    class << self
      # Read path: accepts the live `contents` shape, a legacy `document`-keyed
      # on-disk artifact, or an even older legacy flat artifact.
      def document(response)
        return {} unless response.is_a?(Hash)
        inner = response['contents'] || response['document']
        doc = inner.is_a?(Hash) ? inner : response.select { |k, _| DOC_KEYS.include?(k) }
        fold_legacy_theme(doc, response)
      end

      def metadata(response)
        return {} unless response.is_a?(Hash)
        response.reject do |k, _|
          k == 'contents' || k == 'document' || DOC_KEYS.include?(k) || LEGACY_THEME_KEYS.include?(k)
        end
      end

      # Emitter helper — set the workbook theme on a document hash in the CURRENT
      # shape. Builders should call this instead of assigning the removed
      # themeName/themeOverrides pair. Returns the same hash for chaining.
      def set_theme(doc, name: nil, overrides: nil)
        return doc unless name || (overrides.is_a?(Hash) && !overrides.empty?)
        settings = (doc['settings'] ||= {})
        theme    = (settings['theme'] ||= {})
        theme['name'] = name if name
        if overrides.is_a?(Hash) && !overrides.empty?
          theme['overrides'] = (theme['overrides'] || {}).merge(overrides)
        end
        doc
      end

      # Read the theme back out of either shape (nested settings.theme, or a
      # legacy flat themeName/themeOverrides artifact). Returns {name:, overrides:}.
      def theme(spec)
        d = document(spec)
        t = d.dig('settings', 'theme') || {}
        { 'name' => t['name'], 'overrides' => t['overrides'] || {} }
      end

      # Write path: every live workbook code-rep endpoint requires the wrapper
      # and flat document.elements. Flatten legacy page-nested artifacts at this
      # boundary so older artifacts remain postable during migration. Always
      # writes the current `contents` key -- the legacy /spec endpoints' `document`
      # key is a read-only accommodation for old on-disk artifacts, never emitted.
      def wrap(document_hash, extra: {})
        extra.merge('contents' => flatten_elements(document_hash))
      end

      def workbook_elements(spec)
        elements = document(spec)['elements']
        elements.is_a?(Array) ? elements.select { |element| element.is_a?(Hash) } : []
      end

      # { region_id => [element_id, ...] }, in layout order. A "region" is a
      # page, an overlay, or a **panel** (header/sidebar) — each owns a
      # top-level layout block keyed by id. Live GET specs emit a distinct
      # <Panel> tag for header/sidebar panels (live-confirmed 2026-08-10), and
      # <Overlay> for overlay chrome, alongside <Page> for normal pages; all
      # three carry <Element> leaves, <Container> nested grids, and
      # <TabbedContainer> tab groups the same way. Match on the opening tag and
      # its own closing tag via a backreference so a <Panel> body is never
      # mis-attributed to the preceding <Page>. Keep the two pre-release aliases
      # readable for old snapshots, but do not treat arbitrary XML tags carrying
      # an elementId as workbook ownership.
      def workbook_page_element_ids(spec)
        document(spec)['layout'].to_s
                       .scan(%r{<(Page|Panel|Overlay)\b[^>]*\bid="([^"]*)"[^>]*>(.*?)</\1>}m)
                       .each_with_object({}) do |(_tag, region_id, body), out|
          nodes = body.scan(
            %r{<(?:#{LAYOUT_NODE_TAG_PATTERN})\b[^>]*\belementId="([^"]*)"}m
          )
          out[region_id] = nodes.flatten.uniq
        end
      end

      def workbook_page_by_element(spec)
        doc = document(spec)
        pages = doc['pages'].is_a?(Array) ? doc['pages'].select { |page| page.is_a?(Hash) } : []
        pages_by_id = pages.each_with_object({}) { |page, out| out[page['id']] = page if page['id'] }
        workbook_page_element_ids(doc).each_with_object({}) do |(page_id, element_ids), out|
          page = pages_by_id[page_id] || { 'id' => page_id, 'name' => page_id }
          element_ids.each { |element_id| out[element_id] ||= page }
        end
      end

      def workbook_elements_with_pages(spec)
        page_by_element = workbook_page_by_element(spec)
        workbook_elements(spec).map do |element|
          [element, page_by_element[element['id'] || element['elementId']]]
        end
      end

      private

      def flatten_elements(doc)
        return doc unless doc.is_a?(Hash)
        pages = doc['pages']
        return doc unless pages.is_a?(Array)

        nested_elements = []
        flattened_pages = pages.map do |page|
          copy = page.dup
          nested_elements.concat(Array(copy.delete('elements')))
          copy
        end
        seen = {}
        elements = (Array(doc['elements']) + nested_elements).filter do |element|
          id = element.is_a?(Hash) && element['id']
          next true unless id
          next false if seen[id]

          seen[id] = true
        end
        doc.merge('pages' => flattened_pages, 'elements' => elements)
      end

      # themeName/themeOverrides -> settings.theme.{name,overrides}. Non-mutating:
      # only builds a new hash when a legacy key is actually present, so the
      # common (already-correct) path returns the input untouched.
      def fold_legacy_theme(doc, source)
        name      = doc['themeName']      || source['themeName']
        overrides = doc['themeOverrides'] || source['themeOverrides']
        has_ov    = overrides.is_a?(Hash) && !overrides.empty?
        return doc unless name || has_ov || doc.key?('themeName') || doc.key?('themeOverrides')

        out      = doc.reject { |k, _| LEGACY_THEME_KEYS.include?(k) }
        settings = (out['settings'] || {}).dup
        theme    = (settings['theme'] || {}).dup
        theme['name'] ||= name if name
        theme['overrides'] = (theme['overrides'] || {}).merge(overrides) if has_ov
        return out if theme.empty?

        settings['theme'] = theme
        out['settings'] = settings
        out
      end
    end
  end
end
