# frozen_string_literal: true

require "serpapi"

module Nanobotrb
  module Agent
    module Tools
      class WebSearch < Base
        def initialize(api_key: nil)
          @api_key = api_key || ENV.fetch("SERP_API_KEY", nil)
        end

        def name = "web_search"
        def description = "Search the web for up-to-date information using Google via SerpApi"

        def parameters
          {
            type: "object",
            properties: {
              query: { type: "string", description: "The search query" },
              num: { type: "integer", description: "Number of results to return (default 5, max 10)" }
            },
            required: ["query"]
          }
        end

        def execute(query:, num: 5, **_)
          unless @api_key
            return "Error: SERPAPI_KEY not set. Get one at https://serpapi.com/signup"
          end

          num = [num.to_i, 10].min
          num = 5 if num < 1

          client = SerpApi::Client.new(
            engine: "google",
            api_key: @api_key,
            timeout: 15
          )

          results = client.search(q: query, num: num)
          format_results(results, num)
        rescue StandardError => e
          "Error searching: #{e.message}"
        end

        private

        def format_results(results, limit)
          output = []

          # Answer box / knowledge graph
          if results[:answer_box]
            ab = results[:answer_box]
            answer = ab[:answer] || ab[:snippet] || ab[:result]
            output << "**Answer:** #{answer}" if answer
          end

          if results[:knowledge_graph]
            kg = results[:knowledge_graph]
            output << "**#{kg[:title]}**: #{kg[:description]}" if kg[:description]
          end

          # Organic results
          organic = results[:organic_results] || []
          organic.first(limit).each_with_index do |r, i|
            title = r[:title]
            snippet = r[:snippet]
            link = r[:link]
            output << "#{i + 1}. #{title}\n   #{snippet}\n   #{link}"
          end

          output.empty? ? "No results found for: #{results.dig(:search_parameters, :q)}" : output.join("\n\n")
        end
      end
    end
  end
end
