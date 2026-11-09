# frozen_string_literal: true

module ReportSpec
  module Verifier
    MARKERS = [
      /Unknown column "[^"]+"/,
      /Circular column reference to \[[^\]]+\]/,
      /Dependency not found(?::\s*[^;\n]+)?/i
    ].freeze

    module_function

    def compile_markers(text)
      MARKERS.flat_map { |pattern| text.to_s.scan(pattern) }
             .map { |match| match.is_a?(Array) ? match.first : match }
             .uniq
    end
  end
end
